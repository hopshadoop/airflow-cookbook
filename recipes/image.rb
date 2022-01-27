image_url = node['airflow']['url']
base_filename = File.basename(image_url)

image_name = "#{consul_helper.get_service_fqdn("registry")}:#{node['hops']['docker']['registry']['port']}/airflow:#{node['airflow']['version']}"

remote_file "#{Chef::Config['file_cache_path']}/#{base_filename}" do
  source image_url
  backup false
  action :create_if_missing
  not_if "docker image inspect #{image_name}"
end

#import load registry image
bash "import_image" do
  user "root"
  code <<-EOF
    set -e
    docker load -i #{Chef::Config['file_cache_path']}/#{base_filename}
    docker tag docker.hops.works/airflow:#{node['airflow']['version']} #{image_name}
    docker push #{image_name}
  EOF
  not_if "docker image inspect #{image_name}"
end
