# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "4.52.0"
    }
  }
  required_version = ">= 1.1.0"
}

provider "aws" {
  region = "us-west-2"
}


data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}


resource "tls_private_key" "jenkinskey" {
	algorithm = "RSA"
}
resource "local_file" "jenkins" {
	content = tls_private_key.jenkinskey.private_key_pem
	filename = "jenkins.pem"
}
resource "aws_key_pair" "jenkinshost" {
	key_name = "jenkins"
	public_key = tls_private_key.jenkinskey.public_key_openssh
}


resource "aws_instance" "jenkins" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t2.micro"
  key_name               = aws_key_pair.jenkinshost.key_name
  vpc_security_group_ids = [aws_security_group.jenkins-sg.id]

  user_data = <<-EOF
              #!/bin/bash
              sudo yum update –y
			        sudo wget -o /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo
			        sudo rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key
			        sudo dnf install java-11-amazon-corretto -y
			        sudo yum install jenkins -y
			        sudo systemctl enable jenkins
			        sudo systemctl start jenkins
              EOF
}


resource "aws_vpc" "jenkins" {
  cidr_block = "10.0.0.0/16"
}


resource "aws_subnet" "jenkins-subnet" {
   vpc_id     = aws_vpc.jenkins.id
   cidr_block = "10.0.0.0/16"
}


resource "aws_security_group" "jenkins-sg" {
  name       = "jenkins-sg"
  vpc_id     = aws_vpc.jenkins.id
  depends_on = [aws_vpc.jenkins]
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
   }

  // connectivity to ubuntu mirrors is required to run `apt-get update` and `apt-get install apache2`
  egress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

output "jenkins-address" {
  value = "${aws_instance.jenkins.public_dns}:8080"
}
