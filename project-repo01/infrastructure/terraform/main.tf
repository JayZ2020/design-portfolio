provider "aws" {
  region = "us-east-1" # Change this to your preferred AWS region
}

# VPC Setup
resource "aws_vpc" "main_vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "ecommerce-vpc"
  }
}

resource "aws_subnet" "public_subnet" {
  count = 2
  cidr_block = "10.0.${count.index}.0/24"
  vpc_id     = aws_vpc.main_vpc.id
  map_public_ip_on_launch = true
  availability_zone       = element(data.aws_availability_zones.available.names, count.index)

  tags = {
    Name = "public-subnet-${count.index}"
  }
}

# Internet Gateway for Public Access
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main_vpc.id
  tags = {
    Name = "vpc-igw"
  }
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.main_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "public-route-table"
  }
}

resource "aws_route_table_association" "public_subnet_association" {
  count          = 2
  subnet_id      = aws_subnet.public_subnet[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

# Security Group for EC2 Instances
resource "aws_security_group" "ec2_sg" {
  vpc_id = aws_vpc.main_vpc.id
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ec2-security-group"
  }
}

# Launch Template for EC2 Instances
resource "aws_launch_template" "app_launch_template" {
  name_prefix          = "ecommerce-app"
  image_id             = data.aws_ami.amazon_linux.id # Replace with your AMI ID
  instance_type        = "t2.micro"
  key_name             = "my-key-pair" # Replace with your key pair name
  security_group_names = [aws_security_group.ec2_sg.name]

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y httpd
              systemctl start httpd
              systemctl enable httpd
              echo "Hello, World from $(hostname -f)" > /var/www/html/index.html
            EOF

  tags = {
    Name = "ecommerce-app-instance"
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "app_asg" {
  vpc_zone_identifier = aws_subnet.public_subnet[*].id
  desired_capacity    = 2
  max_size            = 5
  min_size            = 1
  launch_template {
    id      = aws_launch_template.app_launch_template.id
    version = "$Latest"
  }

  tags = [
    {
      key                 = "Name"
      value               = "ecommerce-app-instance"
      propagate_at_launch = true
    },
  ]
}

# Load Balancer
resource "aws_lb" "app_lb" {
  name               = "ecommerce-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.ec2_sg.id]
  subnets            = aws_subnet.public_subnet[*].id

  tags = {
    Name = "ecommerce-lb"
  }
}

# Load Balancer Target Group
resource "aws_lb_target_group" "app_tg" {
  name        = "ecommerce-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main_vpc.id
  target_type = "instance"
}

# Load Balancer Listener
resource "aws_lb_listener" "app_listener" {
  load_balancer_arn = aws_lb.app_lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
  }
}

# Attach Auto Scaling Group to Target Group
resource "aws_autoscaling_attachment" "asg_attachment" {
  autoscaling_group_name = aws_autoscaling_group.app_asg.id
  target_group_arn       = aws_lb_target_group.app_tg.arn
}

# RDS for Database
resource "aws_db_instance" "ecommerce_db" {
  allocated_storage    = 20
  engine               = "mysql"
  engine_version       = "8.0"
  instance_class       = "db.t3.micro"
  name                 = "ecommercedb"
  username             = "admin"
  password             = "your-password" # Replace with a secure password
  publicly_accessible  = false
  multi_az             = true
  storage_encrypted    = true

  vpc_security_group_ids = [aws_security_group.ec2_sg.id]

  tags = {
    Name = "ecommerce-db"
  }
}

# S3 Bucket for Logs and Backups
resource "aws_s3_bucket" "ecommerce_logs" {
  bucket = "ecommerce-logs-${random_id.bucket_id.hex}"
  acl    = "private"

  tags = {
    Name = "ecommerce-logs"
  }
}

resource "random_id" "bucket_id" {
  byte_length = 8
}
