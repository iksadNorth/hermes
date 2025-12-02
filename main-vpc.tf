# VPC 생성 (192.168.45.0/24는 온프레미스용이므로 10.0.0.0/16 사용)
resource "aws_vpc" "hermes" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = { Name = "hermes-vpc" }
}

# Internet Gateway (NAT Gateway용)
resource "aws_internet_gateway" "hermes" {
  vpc_id = aws_vpc.hermes.id

  tags = { Name = "hermes-igw" }
}

# Availability Zones 조회
data "aws_availability_zones" "available" {
  state = "available"
}

# Public Subnet (크롤링 노드용, 보안 그룹으로 외부 접근 차단)
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.hermes.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = { Name = "hermes-public" }
}

# Public Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.hermes.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.hermes.id
  }

  tags = { Name = "hermes-public-rt" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}