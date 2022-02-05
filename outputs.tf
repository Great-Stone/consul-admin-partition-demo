
output "Kube_contexts" {
  value = "All clusters have been authenticated to. Use the following command to see the context you want to use: kubectl config get-contexts. To switch contect use: kubectl config use-context <conetxt-name>"
}

output "server_eip" {
  value = aws_eip.server.public_ip
}