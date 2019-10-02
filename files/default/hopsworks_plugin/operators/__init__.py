from hopsworks_plugin.operators.hopsworks_operator import HopsworksLaunchOperator
from hopsworks_plugin.operators.hopsworks_operator import HopsworksSqoopOperator
from hopsworks_plugin.operators.hopsworks_operator import HopsworksModelServingInstance
from hopsworks_plugin.operators.hopsworks_operator import HopsworksFeatureValidationResult

HOPSWORKS_OPERATORS = [
    HopsworksLaunchOperator,
    HopsworksSqoopOperator,
    HopsworksModelServingInstance,
    HopsworksFeatureValidationResult    
]
