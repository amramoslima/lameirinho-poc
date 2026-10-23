output "playbook_output" {
  description = "Output from execute_playbooks. Only available after apply. Can be used to create an implicit dependency on the playbook execution."
  value = (
    !var.configure_ansible_host ? null :
    var.ansible_vault_password == null
      ? try(terraform_data.execute_playbooks[0].output, null)
      : try(terraform_data.execute_playbooks_with_vault[0].output, null)
  )
}
