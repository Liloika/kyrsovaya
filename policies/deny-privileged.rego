package kubernetes.security

deny[msg] if {
  input.spec.template.spec.containers[_].securityContext.privileged == true
  msg := "Privileged container запрещён"
}

deny[msg] if {
  input.spec.template.spec.containers[_].image == "nginx:latest"
  msg := "Использование latest-тега запрещено"
}
