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

from airflow.sensors.base import BaseSensorOperator
from airflow.exceptions import AirflowException
from airflow.utils.decorators import apply_defaults

from hopsworks_plugin.hooks.hopsworks_hook import HopsworksHook

JOB_SUCCESS_FINAL_APP_STATES = {'FINISHED'}

JOB_FAILED_FINAL_APP_STATES = {'FAILED', 'KILLED', 'FRAMEWORK_FAILURE',
                           'APP_MASTER_START_FAILED', 'INITIALIZATION_FAILED'}

JOB_FINAL_APP_STATES = JOB_FAILED_FINAL_APP_STATES.union(JOB_SUCCESS_FINAL_APP_STATES)

JOB_FAILED_AM_STATUS = {'FAILED', 'KILLED'}

class HopsworksBaseSensor(BaseSensorOperator):
    def __init__(
            self,
            hopsworks_conn_id = 'hopsworks_default',
            job_name = None,
            project_id = None,
            project_name = None,
            *args,
            **kwargs):
        super(HopsworksBaseSensor, self).__init__(*args, **kwargs)
        self.hopsworks_conn_id = hopsworks_conn_id
        self.job_name = job_name
        self.project_id = project_id
        self.project_name = project_name
        if 'hw_api_key' in self.params:
            self.hw_api_key = self.params['hw_api_key']
        else:
            self.hw_api_key = None

    def _get_hook(self):
        return HopsworksHook(self.hopsworks_conn_id, self.project_id, self.project_name, self.owner, self.hw_api_key)


class HopsworksJobFinishSensor(HopsworksBaseSensor):
    """
    Sensor to wait for a job to finish regardless of the final state

    :param job_name: Name of the job in Hopsworks
    :type job_name: str
    :param project_id: Hopsworks Project ID the job is associated with
    :type project_id: int
    :param project_name: Hopsworks Project name this job is associated with
    :type project_name: str
    :param response_check: Custom function to check the return state
    :type response_check: function
    """

    @apply_defaults
    def __init__(
            self,
            hopsworks_conn_id = 'hopsworks_default',
            job_name = None,
            project_id = None,
            project_name = None,
            response_check = None,
            *args,
            **kwargs):
        super(HopsworksJobFinishSensor, self).__init__(hopsworks_conn_id,
                                                       job_name,
                                                       project_id,
                                                       project_name,
                                                       *args,
                                                       **kwargs)
        self.response_check = response_check

    def poke(self, context):
        hook = self._get_hook()
        app_state, am_status = hook.get_job_state(self.job_name)

        if self.response_check:
            return self.response_check(app_state, am_status)

        # If no check was defined, assume that any FINAL state is success
        return app_state.upper() in JOB_FINAL_APP_STATES


class HopsworksJobSuccessSensor(HopsworksBaseSensor):
    """
    Sensor to wait for a successful completion of a job
    If the job fails, the sensor will fail

    :param job_name: Name of the job in Hopsworks
    :type job_name: str
    :param project_id: Hopsworks Project ID the job is associated with
    :type project_id: int
    :param project_name: Hopsworks Project name this job is associated with
    :type project_name: str
    """

    @apply_defaults
    def __init__(
            self,
            hopsworks_conn_id = 'hopsworks_default',
            job_name = None,
            project_id = None,
            project_name = None,
            poke_interval = 10,
            timeout = 3600,
            *args,
            **kwargs):
        super(HopsworksJobSuccessSensor, self).__init__(hopsworks_conn_id,
                                                        job_name,
                                                        project_id,
                                                        project_name,
                                                        *args,
                                                        **kwargs)

    def poke(self, context):
        hook = self._get_hook()
        app_state, am_status = hook.get_job_state(self.job_name)

        if app_state.upper() in JOB_FAILED_FINAL_APP_STATES or \
           (app_state.upper() in JOB_SUCCESS_FINAL_APP_STATES and am_status.upper() in JOB_FAILED_AM_STATUS):
            raise AirflowException("Hopsworks job failed")

        return app_state.upper() in JOB_SUCCESS_FINAL_APP_STATES
