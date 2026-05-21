output "api_public_ip" {
  description = "Public IP of the API VM."
  value       = aws_instance.vm["api"].public_ip
}

output "private_instance_ips" {
  description = "Private IPs for the internal engine and worker VMs."
  value = {
    engine = aws_instance.vm["engine"].private_ip
    math   = aws_instance.vm["math"].private_ip
    caller = aws_instance.vm["caller"].private_ip
  }
}

output "instance_ids" {
  description = "EC2 instance IDs by role."
  value = {
    for role, instance in aws_instance.vm : role => instance.id
  }
}
