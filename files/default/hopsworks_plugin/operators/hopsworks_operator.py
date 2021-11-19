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
import time

from airflow.models import BaseOperator
from airflow.utils.decorators import apply_defaults
from airflow.exceptions import AirflowException

from hopsworks_plugin.hooks.hopsworks_hook import HopsworksHook


class HopsworksAbstractOperator(BaseOperator):
    """
    Abstract Hopsworks operator for some common functionalities across all operators

    :param hopsworks_conn_id: HTTP connection identifier for Hopsworks
    :type hopsworks_conn_id: str
    :param project_id: Hopsworks Project ID this job is associated with. Either this or project_name.
    :type project_id: int
    :param project_name: Hopsworks Project name this job is associated with. Either this or project_id.
    :type project_name: str
    """

    def __init__(
        self,
        hopsworks_conn_id="hopsworks_default",
        project_id=None,
        project_name=None,
        *args,
        **kwargs
    ):
        super(HopsworksAbstractOperator, self).__init__(*args, **kwargs)
        self.hopsworks_conn_id = hopsworks_conn_id
        self.project_id = project_id
        self.project_name = project_name
        if "hw_api_key" in self.params:
            self.hw_api_key = self.params["hw_api_key"]
        else:
            self.hw_api_key = None

    def _get_hook(self):
        return HopsworksHook(
            self.hopsworks_conn_id,
            self.project_id,
            self.project_name,
            self.owner,
            self.hw_api_key,
        )


class HopsworksLaunchOperator(HopsworksAbstractOperator):
    """
    Basic operator to launch jobs on Hadoop through Hopsworks
    Jobs should have already been created in Hopsworks

    :param hopsworks_conn_id: HTTP connection identifier for Hopsworks
    :type hopsworks_conn_id: str
    :param project_id: Hopsworks Project ID this job is associated with. Either this or project_name.
    :type project_id: int
    :param project_name: Hopsworks Project name this job is associated with. Either this or project_id.
    :type project_name: str
    :param job_name: Name of the job in Hopsworks
    :type job_name: str
    :param wait_for_completion: Operator will wait until the job finishes
    :type wait_for_completion: boolean
    :param poke_interval_s: Interval in seconds to poke for job status
    :type poke_interval_s: int
    :param wait_timeout_s: Throw an exception if timeout has reached and job hasn't finished yet
    :type wait_timeout_s: int
    :param wait_for_state: Set of final states to wait for {'FINISHED', 'FAILED', 'KILLED', 'FRAMEWORK_FAILURE',
                           'APP_MASTER_START_FAILED', 'INITIALIZATION_FAILED'}
    :type wait_for_state: set
    :param ignore_failure: Do not fail the task if Job has failed
    :type ignore_failure: boolean
    """

    SUCCESS_APP_STATE = {"FINISHED"}
    FAILED_APP_STATE = {
        "FAILED",
        "KILLED",
        "FRAMEWORK_FAILURE",
        "APP_MASTER_START_FAILED",
        "INITIALIZATION_FAILED",
    }
    FINAL_APP_STATE = SUCCESS_APP_STATE.union(FAILED_APP_STATE)

    FAILED_AM_STATUS = {"FAILED", "KILLED"}

    @apply_defaults
    def __init__(
        self,
        hopsworks_conn_id="hopsworks_default",
        job_name=None,
        project_id=None,
        project_name=None,
        wait_for_completion=True,
        poke_interval_s=1,
        wait_timeout_s=-1,
        wait_for_state=FINAL_APP_STATE,
        ignore_failure=False,
        job_arguments=None,
        *args,
        **kwargs
    ):
        super(HopsworksLaunchOperator, self).__init__(
            hopsworks_conn_id, project_id, project_name, *args, **kwargs
        )
        self.job_name = job_name
        self.wait_for_completion = wait_for_completion
        self.poke_interval_s = poke_interval_s if poke_interval_s > 0 else 1
        self.wait_timeout_s = wait_timeout_s
        self.wait_for_state = wait_for_state
        self.ignore_failure = ignore_failure
        self.job_arguments = job_arguments

    def execute(self, context):
        hook = self._get_hook()
        self.log.debug("Launching job %s", self.job_name)
        execution_id = hook.launch_job(self.job_name, self.job_arguments)

        if self.wait_for_completion:
            self.log.debug("Waiting for job completion")
            time.sleep(5)

            wait_timeout = self.wait_timeout_s
            while True:
                time.sleep(self.poke_interval_s)
                app_state, am_status = hook.get_execution_state(
                    self.job_name, execution_id
                )
                if not self.ignore_failure and self._has_failed(app_state, am_status):
                    raise AirflowException(
                        (
                            "Task failed because Job {0} failed with application state {1} "
                            + "and application master status {2}"
                        ).format(self.job_name, app_state, am_status)
                    )
                if self._has_finished(app_state):
                    self.log.debug("Job %s finished", self.job_name)
                    return
                self.log.debug("Job %s has not finished yet, waiting...", self.job_name)

                if self.wait_timeout_s > -1:
                    wait_timeout -= self.poke_interval_s
                    if wait_timeout < 0:
                        raise AirflowException(
                            "Timeout has been reached while waiting for job {0} to finish".format(
                                self.job_name
                            )
                        )

    def _has_finished(self, app_state):
        self.log.debug("Job state is %s", app_state)
        return app_state.upper() in self.wait_for_state

    def _has_failed(self, app_state, am_status):
        return app_state.upper() in HopsworksLaunchOperator.FAILED_APP_STATE or (
            app_state.upper() in HopsworksLaunchOperator.SUCCESS_APP_STATE
            and am_status.upper() in HopsworksLaunchOperator.FAILED_AM_STATUS
        )


class HopsworksFeatureValidationResult(HopsworksAbstractOperator):
    pass


class HopsworksModelServingInstance(HopsworksAbstractOperator):
    pass
