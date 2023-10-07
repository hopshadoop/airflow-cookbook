import os
from flask_appbuilder.security.manager import AUTH_REMOTE_USER
from hopsworks_auth.hopsworks_jwt_auth import HopsworksAirflowSecurityManager

from airflow.configuration import conf

basedir = os.path.abspath(os.path.dirname(__file__))

# The SQLAlchemy connection string.
SQLALCHEMY_DATABASE_URI = conf.get('core', 'SQL_ALCHEMY_CONN')

# Flask-WTF flag for CSRF
CSRF_ENABLED = True

AUTH_TYPE = AUTH_REMOTE_USER
SECURITY_MANAGER_CLASS = HopsworksAirflowSecurityManager