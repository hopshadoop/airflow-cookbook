from copy import deepcopy
from airflow.config_templates.airflow_local_settings import DEFAULT_LOGGING_CONFIG
import sys, os
import logging

LOGGING_CONFIG = deepcopy(DEFAULT_LOGGING_CONFIG)

LOGGING_CONFIG["handlers"]["general"] = {
    'class': 'logging.handlers.RotatingFileHandler',
    'formatter': 'airflow',
    'filename': "/airflow/logs/airflow.log",
    'maxBytes': 25600,
    'backupCount': 5
}

LOGGING_CONFIG["root"]["handlers"] = ["general"]
LOGGING_CONFIG["loggers"]["flask_appbuilder"]["handlers"] = ["general"]
LOGGING_CONFIG["loggers"]["flask_appbuilder"]["handler"] = ["general"]
LOGGING_CONFIG["loggers"]["flask_appbuilder"]["propagate"] = False


LOGGING_CONFIG["loggers"]["gunicorn.access"] = {
    'handlers': ["general"],
    'level': 'WARN',
    'propagate': False
}

LOGGING_CONFIG["loggers"]["sqlalchemy"] = {
    'handlers': ["general"],
    'level': 'INFO',
    'propagate': False
}