# Day13 — Azure NAT Gateway

## الهدف
هوية خروج ثابتة على مستوى Subnet عبر NAT Gateway دون فتح منافذ inbound على الـ VMs.

## البنية
VMs (no PIP) -> Subnet snet-backend13 -> NAT Gateway natg13weu -> Public IP pip13weu -> Internet
Admin via Bastion: browser -> Bastion (pip-bast13weu) -> vm13a (private)
