provider "aws" {
  region  = "${var.region}"
  version = "~> 2.7"
  profile = var.profile
}

provider "random" {
  version = "~> 2.1"
}

variable "public_key_path" {
  description = <<DESCRIPTION
Path to the SSH public key to be used for authentication.
Ensure this keypair is added to your local SSH agent so provisioners can
connect.

Example: ~/.ssh/kafka_aws.pub
DESCRIPTION
}

resource "random_id" "hash" {
  byte_length = 8
}

variable "key_name" {
  default     = "kafka-benchmark-key"
  description = "Desired name prefix for the AWS key pair"
}

variable "region" {}

variable "ami" {}

variable "profile" {}

variable "instance_types" {
  type = "map"
}

variable "num_instances" {
  type = "map"
}

# Create a VPC to launch our instances into
resource "aws_vpc" "benchmark_vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "Kafka-Benchmark-VPC-${random_id.hash.hex}"
  }
}

# Create an internet gateway to give our subnet access to the outside world
resource "aws_internet_gateway" "kafka" {
  vpc_id = "${aws_vpc.benchmark_vpc.id}"
}

# Grant the VPC internet access on its main route table
resource "aws_route" "internet_access" {
  route_table_id         = "${aws_vpc.benchmark_vpc.main_route_table_id}"
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = "${aws_internet_gateway.kafka.id}"
}

# Create a subnet to launch our instances into
resource "aws_subnet" "benchmark_subnet" {
  vpc_id                  = "${aws_vpc.benchmark_vpc.id}"
  cidr_block              = "10.0.0.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "us-west-2b"
}

# Get public IP of this machine
data "http" "myip" {
  url = "http://ipv4.icanhazip.com"
}

resource "aws_security_group" "benchmark_security_group" {
  name   = "terraform-kafka-${random_id.hash.hex}"
  vpc_id = "${aws_vpc.benchmark_vpc.id}"

  # SSH access from anywhere
  # ingress {
  #   from_port   = 22
  #   to_port     = 22
  #   protocol    = "tcp"
  #   cidr_blocks = ["0.0.0.0/0"]
  # }

  # All ports open within the VPC
  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  # All ports open to this machine
  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["${chomp(data.http.myip.body)}/32"]
  }

  # Prometheus/Dashboard access
  # ingress {
  #   from_port   = 9090
  #   to_port     = 9090
  #   protocol    = "tcp"
  #   cidr_blocks = ["0.0.0.0/0"]
  # }
   ingress {
     from_port   = 3000
     to_port     = 3000
     protocol    = "tcp"
     cidr_blocks = ["0.0.0.0/0"]
   }

  # outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "Benchmark-Security-Group-${random_id.hash.hex}"
  }
}

resource "aws_key_pair" "auth" {
  key_name   = "${var.key_name}-${random_id.hash.hex}"
  public_key = "${file(var.public_key_path)}"
}

resource "aws_instance" "zookeeper" {
  ami                    = "${var.ami}"
  instance_type          = "${var.instance_types["zookeeper"]}"
  key_name               = "${aws_key_pair.auth.id}"
  subnet_id              = "${aws_subnet.benchmark_subnet.id}"
  vpc_security_group_ids = ["${aws_security_group.benchmark_security_group.id}"]
  count                  = "${var.num_instances["zookeeper"]}"
  monitoring             = true

	root_block_device {
		volume_size = 100
		volume_type = "io1"
		iops = 1000
	}

  tags = {
    Name = "zk-${count.index}"
  }
}

resource "aws_instance" "kafka" {
  ami                    = "${var.ami}"
  instance_type          = "${var.instance_types["kafka"]}"
  key_name               = "${aws_key_pair.auth.id}"
  subnet_id              = "${aws_subnet.benchmark_subnet.id}"
  vpc_security_group_ids = ["${aws_security_group.benchmark_security_group.id}"]
  count                  = "${var.num_instances["kafka"]}"
  monitoring             = true

  tags = {
    Name = "kafka-${count.index}"
  }
}

resource "aws_instance" "client" {
  ami                    = "${var.ami}"
  instance_type          = "${var.instance_types["client"]}"
  key_name               = "${aws_key_pair.auth.id}"
  subnet_id              = "${aws_subnet.benchmark_subnet.id}"
  vpc_security_group_ids = ["${aws_security_group.benchmark_security_group.id}"]
  count                  = "${var.num_instances["client"]}"
  monitoring             = true

  tags = {
    Name = "kafka-client-${count.index}"
  }
}

resource "aws_instance" "prometheus" {
  ami                    = "${var.ami}"
  instance_type          = "${var.instance_types["prometheus"]}"
  key_name               = "${aws_key_pair.auth.id}"
  subnet_id              = "${aws_subnet.benchmark_subnet.id}"
  vpc_security_group_ids = ["${aws_security_group.benchmark_security_group.id}"]
  count                  = "${var.num_instances["prometheus"]}"

	root_block_device {
		volume_size = 20
  }

  tags = {
    Name = "prometheus-${count.index}"
  }
}

output "clients" {
  value = {
    for instance in aws_instance.client :
    instance.public_ip => instance.private_ip
  }
}

output "brokers" {
  value = {
    for instance in aws_instance.kafka :
    instance.public_ip => instance.private_ip
  }
}

output "zookeeper" {
  value = {
    for instance in aws_instance.zookeeper :
    instance.public_ip => instance.private_ip
  }
}

output "prometheus_host" {
  value = {
    for instance in aws_instance.prometheus :
    instance.public_ip => instance.private_ip
  }
}

#output "client_ssh_host" {
#  value = "${aws_instance.client.0.public_ip}"
#}
