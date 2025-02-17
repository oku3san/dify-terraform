###################################
# 共通設定
###################################
locals {
  project_name = "main"
  region       = "ap-northeast-1"

  # ネットワーク構成の定義
  # VPCとサブネットのCIDR範囲を設定
  network_config = {
    vpc_cidr = "192.168.0.0/16" # VPC全体のアドレス範囲
    subnets = {
      # パブリックサブネット（インターネットに直接アクセス可能）
      public = [
        { az = "a", cidr = "192.168.0.0/24" }, # AZアの設定
        { az = "c", cidr = "192.168.1.0/24" }  # AZcの設定
      ]
      # プライベートサブネット（インターネットに直接アクセス不可）
      private = [
        { az = "a", cidr = "192.168.100.0/24" }, # AZaの設定
        { az = "c", cidr = "192.168.101.0/24" }  # AZcの設定
      ]
    }
  }

  # VPCエンドポイントの設定
  # AWS Systems Manager接続用のエンドポイント定義
  vpc_endpoints = {
    ssm = {
      service_name = "com.amazonaws.${local.region}.ssm"
      type         = "Interface"
    }
    ssmmessages = {
      service_name = "com.amazonaws.${local.region}.ssmmessages"
      type         = "Interface"
    }
    ec2messages = {
      service_name = "com.amazonaws.${local.region}.ec2messages"
      type         = "Interface"
    }
  }
}

###################################
# VPCの基本設定
###################################
# メインVPCの作成
resource "aws_vpc" "main" {
  cidr_block           = local.network_config.vpc_cidr
  enable_dns_hostnames = true # DNSホスト名を有効化
  enable_dns_support   = true # DNS解決を有効化
}

###################################
# サブネット設定
###################################
# パブリックサブネットの作成
# インターネットゲートウェイを経由してインターネットアクセスが可能
resource "aws_subnet" "public" {
  count                   = length(local.network_config.subnets.public)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = local.network_config.subnets.public[count.index].cidr
  availability_zone       = "${local.region}${local.network_config.subnets.public[count.index].az}"
  map_public_ip_on_launch = true # 起動時にパブリックIPを自動割当
}

# プライベートサブネットの作成
# NATゲートウェイを経由してインターネットアクセスを行う
resource "aws_subnet" "private" {
  count             = length(local.network_config.subnets.private)
  vpc_id            = aws_vpc.main.id
  cidr_block        = local.network_config.subnets.private[count.index].cidr
  availability_zone = "${local.region}${local.network_config.subnets.private[count.index].az}"
}

###################################
# インターネット接続設定
###################################
# インターネットゲートウェイの作成
# パブリックサブネットからインターネットへの直接アクセスを可能にする
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
}

# NAT Gateway用のElastic IP
# 各NATゲートウェイに割り当てる固定IPアドレス
resource "aws_eip" "nat" {
  count  = length(local.network_config.subnets.public)
  domain = "vpc"
}

# NATゲートウェイの作成
# プライベートサブネットからインターネットへのアクセスを可能にする
resource "aws_nat_gateway" "main" {
  count         = length(local.network_config.subnets.public)
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id
  depends_on    = [aws_internet_gateway.main]
}

###################################
# ルーティング設定
###################################
# パブリックルートテーブル
# インターネットゲートウェイへのルートを設定
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0" # すべてのトラフィック
    gateway_id = aws_internet_gateway.main.id
  }
}

# プライベートルートテーブル
# NATゲートウェイへのルートを設定
resource "aws_route_table" "private" {
  count  = length(local.network_config.subnets.private)
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[count.index].id
  }
}

# ルートテーブルの関連付け
# 各サブネットとルートテーブルの紐付け
resource "aws_route_table_association" "public" {
  count          = length(local.network_config.subnets.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count          = length(local.network_config.subnets.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

###################################
# VPCエンドポイント設定
###################################
# VPCエンドポイント用のセキュリティグループ
# エンドポイントへのアクセス制御
resource "aws_security_group" "vpc_endpoint" {
  name        = "${local.project_name}-endpoint-sg"
  description = "Security group for VPC endpoints"
  vpc_id      = aws_vpc.main.id

  # HTTPS通信のみを許可
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [local.network_config.vpc_cidr]
  }
}

# VPCエンドポイント用のIAMポリシー
# エンドポイントの使用許可を設定
data "aws_iam_policy_document" "vpc_endpoint" {
  statement {
    effect    = "Allow"
    actions   = ["*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
  }
}

# VPCエンドポイントの作成
# AWS Systems Manager接続用のエンドポイントを設定
resource "aws_vpc_endpoint" "endpoints" {
  for_each = local.vpc_endpoints

  vpc_id              = aws_vpc.main.id
  service_name        = each.value.service_name
  vpc_endpoint_type   = each.value.type
  subnet_ids          = [aws_subnet.private[0].id]
  security_group_ids  = [aws_security_group.vpc_endpoint.id]
  private_dns_enabled = true # プライベートDNSを有効化
  policy              = data.aws_iam_policy_document.vpc_endpoint.json
}