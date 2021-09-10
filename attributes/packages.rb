# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at

#     http//www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# OS packages needed for the python packages.
default['airflow']['dependencies'] =
  {
    debian:
    {
      default: [{ name: 'python-dev', version: '' },
                { name: 'build-essential', version: '' },
                { name: 'libssl-dev', version: '' },
                { name: 'autoconf', version: '' },
                { name: 'automake', version: '' },
                { name: 'pkg-config', version: '' },
                { name: 'libtool', version: '' },
                { name: 'mysql-client', version: '' },
                { name: 'libmysqlclient-dev', version: '' },
                { name: 'postgresql-client', version: '' },
                { name: 'libpq-dev', version: '' },
                { name: 'freetds-dev', version: '' },
                { name: 'libffi-dev', version: '' },
                { name: 'libffi-dev', version: '' },
                { name: 'libffi-dev', version: '' },
                { name: 'libldap2-dev', version: '' },
                { name: 'libsasl2-dev', version: '' },
                { name: 'libkrb5-dev', version: '' },
                { name: 'libkrb5-dev', version: '' },
                { name: 'freetds-bin', version: '' },
                { name: 'krb5-user', version: '' },
                { name: 'ldap-utils', version: '' },
                { name: 'libffi6', version: '' },
                { name: 'libsasl2-2', version: '' },
                { name: 'libsasl2-modules', version: '' },
                { name: 'libssl1.1', version: '' },
                { name: 'locales', version: '' },
                { name: 'lsb-release', version: '' },
                { name: 'sasl2-bin', version: '' },
#                { name: 'sqlite3', version: '' },
                { name: 'unixodbc', version: '' },
                { name: 'libsasl2-dev', version: '' }]
    },
    rhel:
    {
      default: [{ name: 'gcc', version: '' },
                { name: 'gcc-c++', version: '' },
                { name: 'libjpeg-turbo-devel', version: '' },
                { name: 'zlib-devel', version: '' },
                { name: 'python-devel', version: '' },
                { name: 'mariadb', version: '' },
                { name: 'openssl11', version: '' },
                { name: 'mariadb-devel', version: '' },
                { name: 'postgresql', version: '' },
                { name: 'postgresql-devel', version: '' },
                { name: 'freetds-devel', version: '' },
                { name: 'libffi-devel', version: '' },
                { name: 'libffi-devel', version: '' },
                { name: 'libffi-devel', version: '' },
                { name: 'cyrus-sasl-devel', version: '' },
                { name: 'cyrus-sasl-devel', version: '' },
                { name: 'cyrus-sasl-devel', version: '' },
                { name: 'cyrus-sasl-devel', version: '' },
                { name: 'cyrus-sasl-devel', version: '' }]
    }
  }
