output "namespace_name" {
  description = "Nombre del Namespace creado."
  value       = kubernetes_namespace_v1.app.metadata[0].name
}

output "verification_command" {
  description = "Comando para comprobar el Namespace."
  value       = "kubectl get namespace ${kubernetes_namespace_v1.app.metadata[0].name}"
}
