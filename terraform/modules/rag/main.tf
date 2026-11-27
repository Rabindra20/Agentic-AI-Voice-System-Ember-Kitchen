data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

resource "aws_security_group" "qdrant" {
  name        = "${var.prefix}-QdrantSG"
  description = "Qdrant vector DB"
  vpc_id      = var.vpc_id

  ingress {
    description = "Qdrant REST"
    from_port   = var.env_config.qdrant_port_rest
    to_port     = var.env_config.qdrant_port_rest
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "Qdrant gRPC"
    from_port   = var.env_config.qdrant_port_grpc
    to_port     = var.env_config.qdrant_port_grpc
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.env_config.ec2.allowed_ssh_cidr]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Project = var.prefix }
}

resource "aws_instance" "qdrant" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = var.env_config.ec2.instance_type
  key_name               = var.env_config.ec2.key_pair_name
  subnet_id                   = var.subnet_id
  associate_public_ip_address = true
  vpc_security_group_ids = [aws_security_group.qdrant.id]

  user_data = <<-EOF
    #!/bin/bash
    yum update -y
    yum install -y docker
    systemctl enable docker
    systemctl start docker
    docker pull qdrant/qdrant:latest
    docker run -d \
      --name qdrant \
      --restart unless-stopped \
      -p ${var.env_config.qdrant_port_rest}:6333 \
      -p ${var.env_config.qdrant_port_grpc}:6334 \
      -v /home/ec2-user/qdrant_storage:/qdrant/storage \
      qdrant/qdrant:latest
  EOF

  root_block_device {
    volume_size = var.env_config.ec2.volume_size
    volume_type = var.env_config.ec2.volume_type
  }

  tags = {
    Name    = "${var.prefix}-Qdrant"
    Project = var.prefix
    Note    = "STOP when not testing to control costs"
  }
}
