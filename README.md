# Azure Administrator, Security & Architecture Labs

Hands-on Microsoft Azure infrastructure project covering administration, security, governance, networking, monitoring, resiliency, and cloud architecture.

This repository documents a progressive Azure environment built and extended lab by lab. The individual components are designed to work together as part of a secure and structured Azure infrastructure rather than as isolated exercises.

The implementation applies Microsoft Azure architectural principles and best practices with a strong focus on least privilege, defense in depth, secure networking, governance, resiliency, and operational visibility.

The labs cover practical skills across the core areas of AZ-104, AZ-500, and AZ-305.

## Architecture & Engineering Principles

The environment was designed and implemented with emphasis on:

- Least-privilege access and RBAC
- Identity and access governance
- Network segmentation and controlled connectivity
- Defense-in-depth security
- Secure administrative access
- Private and controlled network communication
- Infrastructure resiliency and availability
- Monitoring and operational visibility
- Storage security and data protection
- Repeatable administration with Azure CLI and PowerShell
- Microsoft Azure recommended architectural practices

## Lab Areas

### Identity & Governance

- Microsoft Entra ID concepts
- Users and groups
- Azure RBAC
- IAM governance
- Role assignments
- Least-privilege access
- Azure governance concepts

### Azure Networking

- Azure Virtual Network
- Subnets
- Network Security Groups
- Network segmentation
- NAT Gateway
- Azure VPN Gateway
- Azure Bastion
- Azure Firewall
- Network Watcher
- Private DNS Resolver
- Secure network architecture

### Application Delivery & Network Security

- Azure Load Balancer
- Application Gateway
- Web Application Firewall
- Controlled inbound and outbound connectivity
- Network security architecture

### Compute & Availability

- Azure Virtual Machines
- Virtual Machine Scale Sets
- Compute availability
- Load balancing
- Resilient infrastructure concepts
- VM networking and connectivity

### Storage & Data Protection

- Azure Storage
- Storage security
- RBAC and access control
- Shared Access Signatures
- Customer-managed key concepts
- Storage protection and data security

### Monitoring & Operations

- Azure Monitor concepts
- Monitoring configuration
- Operational visibility
- Network diagnostics
- Infrastructure troubleshooting

## Automation

The labs include practical administration and deployment using:

- Azure CLI
- PowerShell
- Shell scripting

Automation is used to make deployments and administrative operations more consistent, repeatable, and easier to validate.

## Security Approach

Security is treated as an architectural requirement throughout the project rather than as a separate component.

Key principles include:

- Least privilege
- RBAC-first access control
- Network isolation and segmentation
- Restricted administrative access
- Defense in depth
- Secure resource connectivity
- Data protection
- Monitoring and visibility
- Reduction of unnecessary exposure

## Architecture Focus

The repository demonstrates practical work across several layers of an Azure environment:

```text
Identity & Access
        |
        v
Governance & RBAC
        |
        v
Virtual Networks & Segmentation
        |
        +---- Network Security Groups
        +---- NAT Gateway
        +---- Azure Firewall
        +---- Bastion
        +---- VPN Gateway
        |
        v
Compute & Application Delivery
        |
        +---- Virtual Machines
        +---- Virtual Machine Scale Sets
        +---- Load Balancer
        +---- Application Gateway / WAF
        |
        v
Storage & Data Protection
        |
        v
Monitoring & Operations
```
The objective is to combine these components into secure, manageable, and resilient Azure infrastructure.

Certification Coverage

The practical work in this repository overlaps with major technical domains covered by:

AZ-104: Microsoft Azure Administrator
AZ-500: Microsoft Azure Security Technologies
AZ-305: Designing Microsoft Azure Infrastructure Solutions

The repository is intended to demonstrate practical implementation and architectural understanding beyond certification preparation alone.

Repository Structure

The repository is organized as progressive implementation labs. Examples include:

day2-users-groups-rbac-role/
day3-networking-vnet-subnets-nsg/
day4-compute-vm-vmss/
day5-compute-availability-disks/
day6-storage/
day7-storage-security/
day8-storage-protection/
day9-storage-security/
day10-iam-governance/
day11-monitoring/
day12-lb-agw/
day13-nat-gateway/
day14-azure-firewall/
day15-bastion/
day16-vpn-gateway/
day17-network-watcher/
day18-application-gateway-waf/
day19-private-dns-resolver/
day21-vmss-lb-natgw/

Each lab focuses on a specific Azure capability while contributing to the broader infrastructure and architecture.

Portfolio Context

This repository is part of my hands-on Azure Cloud Engineering portfolio and demonstrates practical work in:

Azure Infrastructure
Azure Administration
Azure Security
Identity and Access Management
Azure Networking
Governance
Monitoring
High Availability
Cloud Architecture
Infrastructure Automation
