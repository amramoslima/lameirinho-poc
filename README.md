# Lameirinho — PowerVS with Single-VPC Landing Zone

Deployable Architecture derivada da arquitectura pública IBM [terraform-ibm-powervs-infrastructure](https://github.com/terraform-ibm-modules/terraform-ibm-powervs-infrastructure), simplificada para o caso de uso da Lameirinho.

---

## Alterações face à arquitectura base

| # | Alteração |
|---|-----------|
| 1 | **Uma única VPC** — a arquitectura base criava 2 VPCs (management + edge). Esta versão cria apenas uma VPC (`pvs-vpc`) com **1 subnet obrigatória** e **até 2 subnets opcionais**. |
| 2 | **VPN Site-to-Site** em vez de Client-to-Site — gateway IBM Cloud VPN (policy-based) na subnet primária. Políticas IKE/IPSec configuráveis por variável. |
| 3 | **Sem Secrets Manager** — não é necessário sem a VPN Client-to-Site. |
| 4 | **Sem Activity Tracker** — atracker e COS de logs não são criados. |
| 5 | **Sem Key Protect** — volumes e buckets não encriptados por KMS dedicado. |
| 6 | **Monitoring sem custo** — não é criada nenhuma instância de monitoring paga. Pode ser ligada uma instância existente (Lite) via `existing_monitoring_instance_crn`. |
| 7 | **Sem SCC Workload Protection** — agente e instância SCC WP não são provisionados. |
| 8 | **Sem Bastion Host** — o jump-box VSI foi removido. O acesso à rede é feito exclusivamente via VPN Site-to-Site ou via `external_access_ip`. |
| 9 | **Serviços de rede na subnet primária** — Squid, DNS forwarder e NTP forwarder correm no `network-services` VSI localizado na subnet primária (que substitui a subnet `edge` da arquitectura original). |
| 10 | **PowerVS com uma única subnet** — apenas `powervs_network` (antes existiam `management_network` + `backup_network`). |
| 11 | **IBM i 7.5 pré-configurado** — instância Power Virtual Server com: OS=IBM i 7.5 EN, CPU=0.25 core (shared, Power11 S1022), RAM=16 GB, Boot Volume=Tier3 100 GB. |
| 12 | **Input completo do peer externo da VPN S2S** — `peer_name`, `peer_address`, `preshared_key`, `on_premises_cidrs` (CIDRs on-premises que poderão alcançar o PowerVS), algoritmos IKE/IPSec e PFS todos configuráveis por variável. |
| 13 | **Transit Gateway explicitamente gerido** — o TGW é criado pelo SLZ; esta solução acrescenta: VPC address prefixes por cada CIDR on-premises (para o TGW os aprender), prefix filters (permit) na conexão VPC do TGW apontando para cada CIDR on-premises, garantindo o caminho PowerVS → TGW → VPC → VPN → on-premises. |

---

## Arquitectura

```
On-premises network (192.168.x.x / …)
        │  IPSec tunnel (IKEv2, AES-256, SHA-256)
        │  peer: <on-premises firewall public IP>
        │
  ┌─────▼──────────────────────────────────────────────┐
  │   VPC  (pvs-vpc)                                   │
  │                                                    │
  │  ┌── subnet: primary ─────────────────────────┐   │
  │  │  • network-services VSI (Squid/DNS/NTP)    │   │
  │  │  • VPN Gateway (policy-based, S2S)         │   │
  │  │    local_cidrs : auto (VPC + PowerVS CIDRs)│   │
  │  │    peer_cidrs  : on_premises_cidrs input   │   │
  │  │  • Public Gateway (outbound internet)      │   │
  │  └────────────────────────────────────────────┘   │
  │                                                    │
  │  [optional] subnet: optional1                      │
  │  [optional] subnet: optional2                      │
  │                                                    │
  │  VPC address prefixes:                             │
  │    one per on-premises CIDR  ──────────────────┐  │
  └──────────────────────┬────────────────────────-┘  │
                         │                         │
               ┌─────────▼───────────┐             │
               │   Transit Gateway   │             │
               │                     │             │
               │  connections:        │             │
               │  • pvs-vpc  (VPC) ◄──────────────┘
               │    + prefix filters               │
               │      (on-prem CIDRs → permit)     │
               │  • PowerVS workspace              │
               └─────────┬───────────┘
                         │
  ┌──────────────────────▼───────────────────────────┐
  │          Power Virtual Server                    │
  │   subnet: pvs-net  (10.51.0.0/24)                │
  │                                                  │
  │   IBM i 7.5 EN                                   │
  │   • S1022 (Power11)  0.25 core shared            │
  │   • 16 GB RAM                                    │
  │   • Boot: Tier3 100 GB                           │
  │                                                  │
  │   Route: on-prem CIDRs → TGW → VPC → VPN        │
  └──────────────────────────────────────────────────┘
```

---

## Pré-requisitos

- Conta IBM Cloud com permissões de administrador
- Acesso ao serviço **Power Virtual Server** na região desejada
- IBM Cloud API Key
- Terraform >= 1.9 (ou IBM Cloud Schematics)
- Par de chaves SSH RSA (2048 ou 4096 bits)

---

## Utilização

### 1. Variáveis mínimas obrigatórias

Cria um ficheiro `terraform.tfvars`:

```hcl
ibmcloud_api_key            = "<API_KEY>"
prefix                      = "lam"
powervs_zone                = "eu-de-1"
powervs_resource_group_name = "Lameirinho-RG"
ssh_public_key              = "<SSH_PUBLIC_KEY>"
ssh_private_key             = <<EOT
-----BEGIN OPENSSH PRIVATE KEY-----
...
-----END OPENSSH PRIVATE KEY-----
EOT
```

### 2. VPN Site-to-Site

A VPN suporta **dois modos**: criação de um novo gateway ou reutilização de um gateway já existente.

#### Modo A — Criar novo gateway

```hcl
site_to_site_vpn = {
  enable = true
  # existing_vpn_gateway_id não definido (null) → cria novo gateway

  # ── Peer (on-premises gateway) ──────────────────────────────────────
  peer_name     = "factory-fw"          # Label usado em nomes de recursos IBM Cloud
  peer_address  = "203.0.113.10"        # IP público do equipamento on-premises
  preshared_key = "SuperSecretKey1!"    # Min. 6 caracteres (sensitive)

  # CIDRs on-premises alcançáveis a partir do PowerVS.
  # Usados como peer_cidrs na ligação VPN e propagados ao Transit Gateway.
  on_premises_cidrs = [
    "192.168.100.0/24",   # LAN servidores
    "192.168.200.0/24",   # LAN utilizadores
  ]

  # ── Tunnel crypto (defaults recomendados) ───────────────────────────
  ike_version    = 2
  ike_auth_alg   = "sha256"
  ike_enc_alg    = "aes256"
  ike_dh_group   = 14
  ipsec_auth_alg = "sha256"
  ipsec_enc_alg  = "aes256"
  ipsec_pfs      = "group_14"

  # ── Local side extras (normalmente vazio) ───────────────────────────
  additional_local_cidrs = []
}
```

> **Nota:** `local_cidrs` é calculado automaticamente (subnets VPC + subnet PowerVS + `additional_local_cidrs`). Não é necessário especificá-los manualmente.

#### Modo B — Reutilizar gateway existente

Quando a organização já tem um IBM Cloud VPN Gateway criado previamente, passa o seu ID e o Terraform **não cria nem modifica** o gateway, as políticas IKE/IPSec nem a ligação VPN. Os `on_premises_cidrs` são aplicados da mesma forma ao Transit Gateway.

```hcl
site_to_site_vpn = {
  enable = true

  # ── Gateway e ligação existentes ────────────────────────────────────
  existing_vpn_gateway_id    = "r010-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
  existing_vpn_connection_id = "r010-yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy"  # opcional, informativo

  # peer_name e peer_address são usados apenas em outputs (não criam recursos)
  peer_name    = "factory-fw"
  peer_address = "203.0.113.10"

  # CIDRs on-premises — ainda necessários para configurar o Transit Gateway
  on_premises_cidrs = [
    "192.168.100.0/24",
    "192.168.200.0/24",
  ]
}
```

> **O que é feito em modo reuse:**
> - Nenhum recurso VPN é criado ou alterado
> - Os VPC address prefixes e os prefix filters do Transit Gateway são criados/actualizados normalmente
> - O output `s2s_vpn_mode` devolve `"reuse"`
> - O output `s2s_vpn_gateway_id` devolve o `existing_vpn_gateway_id` fornecido

### 3. Subnets opcionais

```hcl
vpc_subnet_cidrs = {
  primary   = "10.30.10.0/24"
  optional1 = "10.30.20.0/24"   # set to null to skip
  optional2 = "10.30.30.0/24"   # set to null to skip
}
```

### 4. Personalizar instância IBM i

```hcl
ibmi_instance = {
  name         = "ibmi-prod"
  proc_type    = "shared"
  processors   = "0.25"
  memory       = 16
  sys_type     = "s1022"
  storage_tier = "tier3"
  boot_size    = 100
  # image_id = ""  # deixar vazio para auto-descoberta da imagem IBM i 7.5 EN
}
```

### 5. Deploy

```bash
cd solution-lameirinho
terraform init
terraform plan
terraform apply
```

---

## Variáveis de referência rápida

| Variável | Tipo | Obrigatória | Descrição |
|---|---|---|---|
| `ibmcloud_api_key` | string | ✅ | IBM Cloud API Key |
| `prefix` | string | ✅ | Prefixo único (≤16 chars) |
| `powervs_zone` | string | ✅ | Zona PowerVS (ex: `eu-de-1`) |
| `powervs_resource_group_name` | string | ✅ | Resource group existente |
| `ssh_public_key` | string | ✅ | Chave pública SSH RSA |
| `ssh_private_key` | string | ✅ | Chave privada SSH RSA |
| `external_access_ip` | string | — | IP externo para acesso SSH ao VSI |
| `vpc_subnet_cidrs` | object | — | CIDRs das subnets VPC |
| `site_to_site_vpn.existing_vpn_gateway_id` | string | — | ID de gateway VPN existente — activa modo reuse |
| `site_to_site_vpn.existing_vpn_connection_id` | string | — | ID de ligação VPN existente (informativo) |
| `site_to_site_vpn.peer_name` | string | — | Label do peer on-premises (usado em nomes de recursos) |
| `site_to_site_vpn.peer_address` | string | ✅* | IP público do equipamento VPN on-premises (create mode) |
| `site_to_site_vpn.preshared_key` | string | ✅* | Chave pré-partilhada IKE (sensitive) |
| `site_to_site_vpn.on_premises_cidrs` | list(string) | ✅* | CIDRs on-premises → propagados ao TGW automaticamente |
| `site_to_site_vpn.ike_version` | number | — | Versão IKE (1 ou 2). Default: 2 |
| `site_to_site_vpn.ike_auth_alg` | string | — | Algoritmo autenticação IKE. Default: sha256 |
| `site_to_site_vpn.ike_enc_alg` | string | — | Algoritmo encriptação IKE. Default: aes256 |
| `site_to_site_vpn.ike_dh_group` | number | — | Grupo DH IKE. Default: 14 |
| `site_to_site_vpn.ipsec_auth_alg` | string | — | Algoritmo autenticação IPSec. Default: sha256 |
| `site_to_site_vpn.ipsec_enc_alg` | string | — | Algoritmo encriptação IPSec. Default: aes256 |
| `site_to_site_vpn.ipsec_pfs` | string | — | PFS IPSec. Default: group_14 |
| `site_to_site_vpn.additional_local_cidrs` | list(string) | — | CIDRs IBM Cloud extra para adicionar ao `local_cidrs` |
| `powervs_network` | object | — | Nome e CIDR da subnet PowerVS |
| `ibmi_instance` | object | — | Configuração da instância IBM i |
| `existing_monitoring_instance_crn` | string | — | CRN de instância monitoring existente |
| `tags` | list(string) | — | Tags aplicadas a todos os recursos |

---

## Outputs principais

| Output | Descrição |
|---|---|
| `s2s_vpn_mode` | Modo VPN activo: `create`, `reuse` ou `disabled` |
| `s2s_vpn_gateway_id` | ID efectivo do gateway VPN (novo ou existente) |
| `s2s_vpn_gateway_public_ip` | IPs públicos do gateway VPN — **configurar no equipamento on-premises** (create mode) |
| `s2s_vpn_peer_address` | IP do peer on-premises configurado |
| `s2s_vpn_on_premises_cidrs` | CIDRs on-premises declarados |
| `s2s_vpn_local_cidrs` | CIDRs IBM Cloud anunciados pelo túnel (auto-calculados) |
| `s2s_vpn_connection_status` | Estado da ligação VPN (active / down) |
| `transit_gateway_id` | ID do Transit Gateway |
| `transit_gateway_name` | Nome do Transit Gateway |
| `transit_gateway_connections` | Ligações do TGW (VPC + PowerVS) |
| `tgw_onprem_prefix_filters` | Prefix filters criados por CIDR on-premises |
| `tgw_vpc_connection_id` | ID da ligação VPC no Transit Gateway |
| `network_services_vsi_ip` | IP privado do VSI de serviços de rede |
| `proxy_host_or_ip_port` | Endereço do proxy Squid |
| `powervs_subnet` | Subnet PowerVS (nome, ID, CIDR) |
| `ibmi_instance_id` | ID da instância IBM i |
| `ibmi_network_addresses` | Endereços IP da instância IBM i |

---

## Licença

Apache 2.0 — derivado de [terraform-ibm-modules/terraform-ibm-powervs-infrastructure](https://github.com/terraform-ibm-modules/terraform-ibm-powervs-infrastructure).
