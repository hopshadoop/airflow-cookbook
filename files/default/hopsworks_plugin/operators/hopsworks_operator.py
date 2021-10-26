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
            hopsworks_conn_id = 'hopsworks_default',
            project_id = None,
            project_name = None,
            *args,
            **kwargs):
        super(HopsworksAbstractOperator, self).__init__(*args, **kwargs)
        self.hopsworks_conn_id = hopsworks_conn_id
        self.project_id = project_id
        self.project_name = project_name
        if 'hw_api_key' in self.params:
            self.hw_api_key = self.params['hw_api_key']
        else:
            self.hw_api_key = None
            
    def _get_hook(self):
        return HopsworksHook(self.hopsworks_conn_id, self.project_id, self.project_name, self.owner, self.hw_api_key)

            
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

    SUCCESS_APP_STATE = {'FINISHED'}
    FAILED_APP_STATE = {'FAILED', 'KILLED', 'FRAMEWORK_FAILURE', 'APP_MASTER_START_FAILED', 'INITIALIZATION_FAILED'}
    FINAL_APP_STATE = SUCCESS_APP_STATE.union(FAILED_APP_STATE)

    FAILED_AM_STATUS = {'FAILED', 'KILLED'}
    
    @apply_defaults
    def __init__(
            self,
            hopsworks_conn_id = 'hopsworks_default',
            job_name = None,
            project_id = None,
            project_name = None,
            wait_for_completion = True,
            poke_interval_s = 1,
            wait_timeout_s = -1,
            wait_for_state = FINAL_APP_STATE,
            ignore_failure = False,
            job_arguments = None,
            *args,
            **kwargs):
        super(HopsworksLaunchOperator, self).__init__(hopsworks_conn_id,
                                                      project_id,
                                                      project_name,
                                                      *args,
                                                      **kwargs)
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
        hook.launch_job(self.job_name, self.job_arguments)

        if self.wait_for_completion:
            self.log.debug("Waiting for job completion")
            time.sleep(5)
            
            wait_timeout = self.wait_timeout_s
            while True:
                time.sleep(self.poke_interval_s)
                app_state, am_status = hook.get_job_state(self.job_name)
                if not self.ignore_failure and self._has_failed(app_state, am_status):
                    raise AirflowException(("Task failed because Job {0} failed with application state {1} " +    
                                            "and application master status {2}")
                                           .format(self.job_name, app_state, am_status))
                if self._has_finished(app_state):
                    self.log.debug("Job %s finished", self.job_name)
                    return
                self.log.debug("Job %s has not finished yet, waiting...", self.job_name)
                
                if self.wait_timeout_s > -1:
                    wait_timeout -= self.poke_interval_s
                    if wait_timeout < 0:
                        raise AirflowException("Timeout has been reached while waiting for job {0} to finish"
                                               .format(self.job_name))

    def _has_finished(self, app_state):
        self.log.debug("Job state is %s", app_state)
        return app_state.upper() in self.wait_for_state

    def _has_failed(self, app_state, am_status):
        return app_state.upper() in HopsworksLaunchOperator.FAILED_APP_STATE or \
                (app_state.upper() in HopsworksLaunchOperator.SUCCESS_APP_STATE and \
                am_status.upper() in HopsworksLaunchOperator.FAILED_AM_STATUS)

    
class HopsworksModelServingInstance(HopsworksAbstractOperator):
    """
    Hopsworks operator to administer model serving instances in Hopsworks.
    You can create a new model serving instance, update an existing one or
    stop an instance.

    :param hopsworks_conn_id: HTTP connection identifier for Hopsworks
    :type hopsworks_conn_id: str
    :param project_id: Hopsworks Project ID this job is associated with. Either this or project_id.
    :type project_id: int
    :param project_name: Hopsworks Project name this job is associated with. Either this or project_name.
    :type project_name: str
    :param model_name: Name of the model to be served
    :type model_name: str
    :param artifact_path: Path in HDFS where the model is saved
    :type artifact_path: str
    :param model_version: Model version to serve, defaults to 1
    :type model_version: int
    :param action: Action to perform after creating or updating an instance
    Available actions are START and STOP
    :type action: str
    :param batching_enabled: Enable batch for model serving
    :type batching_enabled: boolean
    :param serving_instances: Relevant only when Kubernetes is deployed. Number of
    serving instances to be created for serving the model.
    :param kafka_topic_name: Kafka topic name to publish serving requests. Possible values are:
    NONE: Do not create a Kafka topic. Serving requests will not be published
    CREATE: Create a new unique Kafka topic
    KAFKA_TOPIC_NAME: Name of an existing Kafka topic
    :type kafka_topic_name: str
    :param kafka_num_partitions: Number of partitions when creating a new Kafka topic. Cannot be updated.
    :type kafka_num_partitions: int
    :param kafka_num_replicas: Number of replicas when creating a new kafka topic. Cannot be updated.
    :type kafka_num_replicas: int
    """
    serving_actions = ["START", "STOP"]
    
    @apply_defaults
    def __init__(
            self,
            hopsworks_conn_id = 'hopsworks_default',
            project_id = None,
            project_name = None,
            model_name = None,
            artifact_path = None,
            model_version = 1,
            action = "START",
            serving_type = "TENSORFLOW",
            batching_enabled = False,
            serving_instances = 1,
            kafka_topic_name = None,
            kafka_num_partitions = 1,
            kafka_num_replicas = 1,
            *args,
            **kwargs):
        super(HopsworksModelServingInstance, self).__init__(hopsworks_conn_id,
                                                            project_id,
                                                            project_name,
                                                            *args,
                                                            **kwargs)
        self.model_name = model_name
        self.artifact_path = artifact_path
        self.model_version = model_version
        self.action = action
        self.serving_type = serving_type.upper()
        self.batching_enabled = batching_enabled
        self.serving_instances = serving_instances
        self.kafka_topic_name = kafka_topic_name
        self.kafka_num_partitions = kafka_num_partitions
        self.kafka_num_replicas = kafka_num_replicas

    def execute(self, context):
        if not self.action.upper() in HopsworksModelServingInstance.serving_actions:
            raise AirflowException("Unknown model serving action {0} Valid actions are: START, STOP"
                                   .format(self.action))
        
        if self.model_name is None:
            raise AirflowException("Model name cannot be empty")

        hook = self._get_hook()
        serving_instance = self._find_model_serving_instance_by_model_name(hook, self.model_name)

        if self.action.upper() == "START":
            self._start_model_serving(hook, serving_instance)
        elif self.action.upper() == "STOP":
            self._stop_model_serving(hook, serving_instance)
        
    def _start_model_serving(self, hook, serving_instance):
        serving_params = {}
        kafka_topic_params = {}
        if serving_instance:
            # If serving instance with the same name exists,
            # update it instead of creating a new one
            serving_params['id'] = serving_instance['id']
            if self.kafka_topic_name:
                # If user provided a new Kafka topic name, update it
                kafka_topic_params['name'] = self.kafka_topic_name
                kafka_topic_params['numOfPartitions'] = self.kafka_num_partitions
                kafka_topic_params['numOfReplicas'] = self.kafka_num_replicas
            else:
                # Otherwise use the previous if it had any
                stored_kafka_params = serving_instance.get('kafkaTopicDTO', None)
                if stored_kafka_params:
                    kafka_topic_params['name'] = stored_kafka_params['name']
        else:
            kafka_topic_params['name'] = self.kafka_topic_name if self.kafka_topic_name else "NONE"
            kafka_topic_params['numOfPartitions'] = self.kafka_num_partitions
            kafka_topic_params['numOfReplicas'] = self.kafka_num_replicas
            
        serving_params['kafkaTopicDTO'] = kafka_topic_params
        serving_params['batchingEnabled'] = self.batching_enabled
        serving_params['name'] = self.model_name
        serving_params['artifactPath'] = self.artifact_path
        serving_params['modelVersion'] = self.model_version
        serving_params['requestedInstances'] = self.serving_instances
        serving_params['servingType'] = self.serving_type

        self.log.debug("Create model serving parameters: %s", serving_params)

        hook.create_update_serving_instance(serving_params)

        # If instance does not exist, start it
        # If instance exists, it is an update and Hopsworks
        # will handle restarting the serving instance
        if not serving_instance:
            # Get all model serving instances to get the ID of the newly created instance
            serving_instance = self._find_model_serving_instance_by_model_name(hook, self.model_name)
            self.log.debug("Starting model serving instance %s", self.model_name)
            hook.start_model_serving_instance(serving_instance['id'])
                
    def _stop_model_serving(self, hook, serving_instance):
        if not serving_instance:
            raise AirflowException("Trying to stop model serving instance, but instance does not exist!")
        self.log.debug("Stopping model serving instance %s", serving_instance['modelName'])
        hook.stop_model_serving_instance(serving_instance['id'])

    def _find_model_serving_instance_by_model_name(self, hook, model_name):
        serving_instances = hook.get_model_serving_instances()
        for si in serving_instances:
            if model_name == si['name']:
                return si
        return None
