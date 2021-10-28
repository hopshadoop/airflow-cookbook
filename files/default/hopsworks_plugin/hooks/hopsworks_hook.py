# -*- coding: utf-8 -*-
#
# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.

import os
import sys
import hashlib
import requests
import glob

from time import sleep
from requests import exceptions as requests_exceptions
from requests.auth import AuthBase
from json.decoder import JSONDecodeError as json_exception

from airflow.hooks.base_hook import BaseHook
from airflow.utils.log.logging_mixin import LoggingMixin
from airflow.exceptions import AirflowException
from airflow import configuration
from airflow.models import Connection

PY3 = sys.version_info[0] == 3

if PY3:
    from urllib import parse as urlparse
else:
    import urlparse

AIRFLOW_HOME_ENV = "AIRFLOW_HOME"
JWT_FILE_SUFFIX = ".jwt"

# Key for project ID for PROJECT_INFO_NAME response
PROJECT_ID_KEY = "projectId"
# Key for project name for PROJECT_INFO_ID response
PROJECT_NAME_KEY = "projectName"

BASE_API = "hopsworks-api/api"

##############
## Jobs API ##
##############

RUN_JOB = ("POST", BASE_API + "/project/{project_id}/jobs/{job_name}/executions")
EXECUTION_STATE = (
    "GET",
    BASE_API + "/project/{project_id}/jobs/{job_name}/executions/{execution_id}",
)
# Get the latest execution
LAST_EXECUTION_STATE = (
    "GET",
    BASE_API
    + "/project/{project_id}/jobs/{job_name}/executions?sort_by=submissiontime:desc&limit=1",
)

##################
## Projects API ##
##################

# Get Project info from name
PROJECT_INFO_NAME = ("GET", BASE_API + "/project/getProjectInfo/{project_name}")
# Get Project info from id
PROJECT_INFO_ID = ("GET", BASE_API + "/project/{project_id}")


class HopsworksHook(BaseHook, LoggingMixin):
    """
    Hook to interact with Hopsworks

    :param hopsworks_conn_id: The name of Hopsworks connection to use.
    :type hopsworks_conn_id: str
    :param project_id: Project ID the job is associated with.
    :type project_id: int
    :param project_name: Project name the job is associated with.
    :type project_name: str
    :param owner: Hopsworks username
    :type owner: str
    """

    def __init__(
        self,
        hopsworks_conn_id="hopsworks_default",
        project_id=None,
        project_name=None,
        owner=None,
        hw_api_key=None,
    ):
        self.hopsworks_conn_id = hopsworks_conn_id
        self.owner = owner
        self.hopsworks_conn = self.get_connection(hopsworks_conn_id)
        self.project_name = project_name
        self.hw_api_key = hw_api_key

        if project_id is None:
            self.project_id, _ = self._get_project_info(project_id, project_name)
        else:
            self.project_id = project_id

        if project_name is None:
            _, self.project_name = self._get_project_info(project_id, project_name)

    def get_connection(self, connection_id):
        try:
            conn = super().get_connection(connection_id)
            if not conn.schema:
                self.log.warn(
                    "Connection schema for {} was not set, setting https".format(
                        connection_id
                    )
                )
                conn.schema = "https"
            return conn
        except AirflowException:
            self.log.warn(
                "Didn't find connection with ID: {} - falling back to configuration".format(
                    connection_id
                )
            )
            hopsworks_host = configuration.conf.get("webserver", "hopsworks_host")
            hopsworks_port = configuration.conf.getint("webserver", "hopsworks_port")
            return Connection(
                conn_id=connection_id,
                schema="https",
                host=self._parse_host(hopsworks_host),
                port=hopsworks_port,
            )

    def launch_job(self, job_name, args):
        """Function for launching a job to Hopsworks. The call does not wait for job
        completion, use HopsworksSensor for this purpose.

        :param job_name: Name of the job to be launched in Hopsworks
        :type job_name: str
        :type args: runtime arguments of this execution

        :returns: Execution ID of the job just launched
        :rtype: int
        """
        method, endpoint = RUN_JOB
        endpoint = endpoint.format(project_id=self.project_id, job_name=job_name)
        response = self._do_api_call(method, endpoint, args)
        return response["id"]

    def get_execution_state(self, job_name, execution_id):
        """
        Function to get the state of an execution

        :param job_name: Name of the job in Hopsworks
        :type job_name: str
        :param execution_id: The ID of the Hopsworks execution
        :type job_name: int
        """
        method, endpoint = EXECUTION_STATE
        endpoint = endpoint.format(
            project_id=self.project_id, job_name=job_name, execution_id=execution_id
        )
        item = self._do_api_call(method, endpoint)
        return item["state"], item["finalStatus"]

    def get_last_execution_state(self, job_name):
        """
        Function to get the state of the last execution

        :param job_name: Name of the job in Hopsworks
        :type job_name: str
        """
        method, endpoint = LAST_EXECUTION_STATE
        endpoint = endpoint.format(project_id=self.project_id, job_name=job_name)
        response = self._do_api_call(method, endpoint)
        item = response["items"][0]
        return item["state"], item["finalStatus"]

    def _do_api_call(self, method, endpoint, data=None):
        url = "{schema}://{host}:{port}/{endpoint}".format(
            schema=self.hopsworks_conn.schema,
            host=self.hopsworks_conn.host,
            port=self.hopsworks_conn.port,
            endpoint=endpoint,
        )
        if "GET" == method:
            requests_method = requests.get
        elif "POST" == method:
            requests_method = requests.post
        elif "PUT" == method:
            requests_method = requests.put
        else:
            raise AirflowException("Unexpected HTTP method: " + method)

        attempts = 1
        while True:
            try:
                if self.hw_api_key:
                    auth = APIKeyAuthorization(self.hw_api_key)
                else:
                    jwt = self._parse_jwt_for_user()
                    auth = JWTAuthorization(jwt)
                # Until we find a better approach to load trust anchors and
                # bypass hostname verification, disable verify
                response = requests_method(url, auth=auth, verify=False, data=data)
                response.raise_for_status()
                try:
                    return response.json()
                except json_exception:
                    # No content in respose 201 CREATED
                    return ""
            except requests_exceptions.SSLError as ex:
                raise AirflowException(ex)
            except requests_exceptions.RequestException as ex:
                if attempts > 3:
                    raise AirflowException(
                        "Error making HTTP request. Response: {0} - Status Code: {1}".format(
                            ex.response.content, ex.response.status_code
                        )
                    )
                self.log.warn("Error making HTTP request, retrying...")
                self.log.warn(
                    "Code {0} - Reason {1}".format(
                        ex.response.status_code, ex.response.content
                    )
                )
                attempts += 1
                sleep(1)

    def _get_project_info(self, project_id, project_name):
        if project_id is None and project_name is None:
            raise AirflowException(
                "At least project_id or project_name should be specified"
            )
        if project_id is None:
            method, endpoint = PROJECT_INFO_NAME
            endpoint = endpoint.format(project_name=project_name)
        elif project_name is None:
            method, endpoint = PROJECT_INFO_ID
            endpoint = endpoint.format(project_id=project_id)

        response = self._do_api_call(method, endpoint)
        if PROJECT_ID_KEY not in response:
            raise AirflowException(
                "Could not parse {0} from REST response".format(PROJECT_ID_KEY)
            )
        project_id_resp = response[PROJECT_ID_KEY]

        if PROJECT_NAME_KEY not in response:
            raise AirflowException(
                "Could not parse {0} from REST response".format(PROJECT_NAME_KEY)
            )
        project_name_resp = response[PROJECT_NAME_KEY]
        return project_id_resp, project_name_resp

    def _parse_host(self, host):
        """
        Host should be just the hostname or ip address
        Remove protocol or any endpoints from the host

        """
        parsed_host = urlparse.urlparse(host).hostname
        if parsed_host:
            # Host contains protocol
            return parsed_host
        return host

    def _get_airflow_home(self):
        """
        Discover Airflow home. Environment variable takes precedence over configuration
        """
        if AIRFLOW_HOME_ENV in os.environ:
            return os.environ[AIRFLOW_HOME_ENV]
        airflow_home = configuration.conf.get("core", "airflow_home")
        if not airflow_home:
            raise AirflowException(
                "Airflow home is not set in configuration, nor in $AIRFLOW_HOME"
            )
        return airflow_home

    def _generate_secret_dir(self):
        """
        Generate the secret project directory where the JWT file
        and X.509 should be located
        """
        airflow_home = self._get_airflow_home()
        # First try with owner
        digest = hashlib.sha256(str(self.owner).encode("UTF-8")).hexdigest()
        secret_dir = os.path.join(airflow_home, "secrets", digest)
        if os.path.exists(secret_dir):
            return secret_dir

        # Then try with project_id for backward compatibility
        if not self.project_id:
            raise AirflowException("Hopsworks Project ID is not set")
        digest = hashlib.sha256(str(self.project_id).encode("UTF-8")).hexdigest()
        return os.path.join(airflow_home, "secrets", digest)

    def _parse_jwt_for_user(self):
        """
        Read JWT for the user from the secret project directory.

        WARNING: JWT is renewed automatically by Hopsworks, so caching
        will break things!!!
        """
        if not self.owner:
            raise AirflowException("Owner of the DAG is not specified")

        secret_dir = self._generate_secret_dir()

        # When hook is constructed and project name is not provided
        # we should get the first token available for this user.
        if self.project_name is None:
            jwt_regex = os.path.join(secret_dir, "*__{0}.jwt".format(self.owner))
            tokens_found = glob.glob(jwt_regex)
            if not tokens_found:
                raise AirflowException(
                    "Could not find any token related to user {0}".format(self.owner)
                )
            jwt_token_file = tokens_found[0]
        else:
            filename = "{0}__{1}{2}".format(
                self.project_name, self.owner, JWT_FILE_SUFFIX
            )
            jwt_token_file = os.path.join(secret_dir, filename)

        if not os.path.isfile(jwt_token_file):
            raise AirflowException(
                "Could not read JWT file for user {}".format(self.owner)
            )
        with open(jwt_token_file, "r") as fd:
            return fd.read().strip()


class JWTAuthorization(AuthBase):
    def __init__(self, token):
        self.token = token

    def __call__(self, request):
        request.headers["Authorization"] = "Bearer {0}".format(self.token)
        return request


class APIKeyAuthorization(AuthBase):
    def __init__(self, key):
        self.key = key

    def __call__(self, request):
        request.headers["Authorization"] = "ApiKey {0}".format(self.key)
        return request
