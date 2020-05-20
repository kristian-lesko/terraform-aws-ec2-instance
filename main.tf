locals {
  is_t_instance_type = replace(var.instance_type, "/^t(2|3|3a){1}\\..*$/", "1") == "1" ? true : false
  instance_eip_ips = split(
    ",",
    var.reuse_eip_ips ? join(",", var.instance_eip_ids) : join(",", aws_eip.instance.*.id),
  )
}

resource "aws_instance" "this" {
  count = var.instance_count

  ami              = var.ami
  instance_type    = var.instance_type
  user_data        = element(data.template_file.userdata.*.rendered, count.index)
#  user_data        = user_data_template == "" ? var.user_data : element(data.template_file.userdata.*.rendered, count.index)
  user_data_base64 = var.user_data_base64
  subnet_id = length(var.network_interface) > 0 ? null : element(
    distinct(compact(concat([var.subnet_id], var.subnet_ids))),
    count.index,
  )
  key_name               = var.key_name
  monitoring             = var.monitoring
  get_password_data      = var.get_password_data
  vpc_security_group_ids = var.vpc_security_group_ids
  iam_instance_profile   = var.iam_instance_profile

  associate_public_ip_address = var.associate_public_ip_address
  private_ip                  = length(var.private_ips) > 0 ? element(var.private_ips, count.index) : var.private_ip
  ipv6_address_count          = var.ipv6_address_count
  ipv6_addresses              = var.ipv6_addresses

  ebs_optimized = var.ebs_optimized

  dynamic "root_block_device" {
    for_each = var.root_block_device
    content {
      delete_on_termination = lookup(root_block_device.value, "delete_on_termination", null)
      encrypted             = lookup(root_block_device.value, "encrypted", null)
      iops                  = lookup(root_block_device.value, "iops", null)
      kms_key_id            = lookup(root_block_device.value, "kms_key_id", null)
      volume_size           = lookup(root_block_device.value, "volume_size", null)
      volume_type           = lookup(root_block_device.value, "volume_type", null)
    }
  }

  dynamic "ebs_block_device" {
    for_each = var.ebs_block_device
    content {
      delete_on_termination = lookup(ebs_block_device.value, "delete_on_termination", null)
      device_name           = ebs_block_device.value.device_name
      encrypted             = lookup(ebs_block_device.value, "encrypted", null)
      iops                  = lookup(ebs_block_device.value, "iops", null)
      kms_key_id            = lookup(ebs_block_device.value, "kms_key_id", null)
      snapshot_id           = lookup(ebs_block_device.value, "snapshot_id", null)
      volume_size           = lookup(ebs_block_device.value, "volume_size", null)
      volume_type           = lookup(ebs_block_device.value, "volume_type", null)
    }
  }

  dynamic "ephemeral_block_device" {
    for_each = var.ephemeral_block_device
    content {
      device_name  = ephemeral_block_device.value.device_name
      no_device    = lookup(ephemeral_block_device.value, "no_device", null)
      virtual_name = lookup(ephemeral_block_device.value, "virtual_name", null)
    }
  }

  dynamic "network_interface" {
    for_each = var.network_interface
    content {
      device_index          = network_interface.value.device_index
      network_interface_id  = lookup(network_interface.value, "network_interface_id", null)
      delete_on_termination = lookup(network_interface.value, "delete_on_termination", false)
    }
  }

  source_dest_check                    = length(var.network_interface) > 0 ? null : var.source_dest_check
  disable_api_termination              = var.disable_api_termination
  instance_initiated_shutdown_behavior = var.instance_initiated_shutdown_behavior
  placement_group                      = var.placement_group
  tenancy                              = var.tenancy

  tags = merge(
    {
      "Name" = var.instance_count > 1 || var.use_num_suffix ? format("%s-%d", var.name, count.index + 1) : var.name
    },
    var.tags,
  )

  volume_tags = merge(
    {
      "Name" = var.instance_count > 1 || var.use_num_suffix ? format("%s-%d", var.name, count.index + 1) : var.name
    },
    var.volume_tags,
  )

  credit_specification {
    cpu_credits = local.is_t_instance_type ? var.cpu_credits : null
  }

  lifecycle {
    create_before_destroy = true
    ignore_changes = [
      # Ignore changes to tags, e.g. because a management agent
      # updates these based on some ruleset managed elsewhere.
      tags, user_data, user_data_base64, ami,
    ]
  }
#  provisioner "remote-exec" {
#    inline = var.remote-exec-inline
#    connection {
#      type     = "ssh"
#      user     = var.remote-exec-user
#      host     = self.public_ip
#      private_key = file(var.private_key_location)
#    }
#  }

}

#resource "null_resource" "this" {
#  provisioner "remote-exec" {
#    inline = var.remote-exec
#    connection {
#      type     = "ssh"
#      user     = "ubuntu"
#      host     = aws_instance.this.*.public_ip
#    }
#  }
#}

resource "aws_eip" "instance" {
  count = var.assign_eip && false == var.reuse_eip_ips ? var.instance_count : 0

  vpc = true

  tags = merge(
    {
      "Name" = format(
        "%s-%s",
        var.name,
        element(aws_instance.this, count.index),
      )
    },
    var.tags,
    var.instance_eip_tags,
  )
}

resource "aws_eip_association" "eip_assoc" {
  count = var.assign_eip ? var.instance_count : 0
  instance_id = element(
    aws_instance.this.*.id,
    count.index,
  )

  allocation_id = element(
    local.instance_eip_ips,
    count.index,
  )
}

data template_file "userdata" {
  count = var.instance_count

  template = file("${var.user_data_template}")

  vars = {
    freeipa_otp = element(random_password.freeipa_otp.*.result,count.index,)
    clusterid = var.clusterid
    subcluster = var.subcluster
    role = var.role
    datacenter = var.datacenter
    environment = var.environment
    puppet_master_key = var.puppet_master_key
    vault_gpg_key = var.vault_gpg_key
  }
}

resource "random_password" "freeipa_otp" {
  count = var.instance_count

  length = 32
  special = false
  keepers = {
     uuid = uuid()
#    uuid = element(
#      aws_instance.this.*.id,
#      count.index,
#    )
  }
}

