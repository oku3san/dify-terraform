# ###################################
# # 共通設定
# ###################################
# # プロジェクト全体で使用する共通の変数と設定
# locals {
#   name_prefix = var.project
# }
#
# ###################################
# # セキュリティグループ
# ###################################
# # ALB（Application Load Balancer）用のセキュリティグループ
# # パブリックからのアクセスを制御するためのセキュリティ設定
# resource "aws_security_group" "alb" {
#   name        = "${local.name_prefix}-alb-sg"
#   description = "Security group for ALB"
#   vpc_id      = aws_vpc.main.id
#
#   # HTTP(80)とHTTPS(443)のインバウンドルールを動的に生成
#   # パブリックインターネットからのアクセスを許可
#   dynamic "ingress" {
#     for_each = [80, 443]
#     content {
#       description      = "Allow ${ingress.value == 80 ? "HTTP" : "HTTPS"} from anywhere"
#       from_port        = ingress.value
#       to_port          = ingress.value
#       protocol         = "tcp"
#       cidr_blocks      = ["0.0.0.0/0"] # すべてのIPv4アドレスからのアクセスを許可
#       ipv6_cidr_blocks = ["::/0"]      # すべてのIPv6アドレスからのアクセスを許可
#     }
#   }
#
#   # アウトバウンドルール：すべてのトラフィックを許可
#   egress {
#     description      = "Allow all outbound traffic"
#     from_port        = 0
#     to_port          = 0
#     protocol         = "-1" # すべてのプロトコル
#     cidr_blocks      = ["0.0.0.0/0"]
#     ipv6_cidr_blocks = ["::/0"]
#   }
# }
#
#
# ###################################
# # CloudFront ディストリビューション
# ###################################
# resource "aws_cloudfront_distribution" "dify" {
#   provider            = aws.global
#   enabled             = true # ディストリビューションを有効化
#   is_ipv6_enabled     = true # IPv6 を有効化
#   comment             = "CloudFront distribution for ALB"
#   default_root_object = "" # デフォルトのルートオブジェクト
#
#   # オリジン設定（ALBを紐づけ）
#   origin {
#     domain_name = aws_lb.main.dns_name
#     origin_id   = "alb-origin"
#
#     vpc_origin_config {
#       vpc_origin_id            = aws_cloudfront_vpc_origin.alb.id
#       origin_keepalive_timeout = 5  // CloudFront がオリジンへの接続を維持する秒数
#       origin_read_timeout      = 30 // CloudFront がオリジンからの応答を待機する秒数
#     }
#   }
#
#   # キャッシュビヘイビア設定
#   default_cache_behavior {
#     allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
#     cached_methods   = ["GET", "HEAD"]
#     target_origin_id = "alb-origin"
#
#     # forwarded_valuesの代わりにcache_policy_idを使用
#     cache_policy_id          = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" # CachingDisabled policy ID
#     origin_request_policy_id = "216adef6-5c7f-47e4-b989-5492eafa07d3" # AllViewer policy ID
#
#     viewer_protocol_policy = "redirect-to-https"
#   }
#
#   # 地理的制限の設定
#   restrictions {
#     geo_restriction {
#       restriction_type = "none" # 地理的制限なし
#     }
#   }
#
#   # 利用する CloudFront ドメインのSSL設定
#   viewer_certificate {
#     cloudfront_default_certificate = true # デフォルトのCloudFront証明書を使用
#   }
# }
#
# resource "aws_cloudfront_vpc_origin" "alb" {
#   vpc_origin_endpoint_config {
#     name                   = "dify-vpc-origin"
#     arn                    = aws_lb.main.arn # ARN of the associated load balancer
#     http_port              = 80
#     https_port             = 443
#     origin_protocol_policy = "http-only"
#
#     origin_ssl_protocols {
#       items    = ["TLSv1.2"]
#       quantity = 1
#     }
#   }
# }
#
# ###################################
# # ログ用のS3バケット (CloudFront ログ)
# ###################################
# resource "aws_s3_bucket" "logs" {
#   bucket        = "${local.name_prefix}-cloudfront-logs"
#   force_destroy = true
# }
#
# ###################################
# # Application Load Balancer（ALB）設定
# ###################################
# # メインのALBリソース
# # パブリックサブネットに配置し、インターネットからのトラフィックを受け付ける
# resource "aws_lb" "main" {
#   name               = "${local.name_prefix}-alb"
#   internal           = false         # インターネット向けALB（パブリック）
#   load_balancer_type = "application" # ALBタイプの指定
#   security_groups    = [aws_security_group.alb.id]
#   # パブリックサブネットにALBを配置
#   subnets = [for subnet in aws_subnet.private : subnet.id]
# }
#
# # ALBターゲットグループ
# # バックエンドサービスのヘルスチェックと負荷分散の設定
# resource "aws_lb_target_group" "app" {
#   name     = "${local.name_prefix}-tg"
#   port     = 80 # HTTPポート
#   protocol = "HTTP"
#   vpc_id   = aws_vpc.main.id
#
#   # アプリケーションのヘルスチェック設定
#   health_check {
#     enabled             = true
#     healthy_threshold   = 2              # 正常判定になるまでのチェック回数
#     interval            = 30             # ヘルスチェックの間隔（秒）
#     matcher             = "200"          # 正常判定とするHTTPステータスコード
#     port                = "traffic-port" # トラフィックと同じポートを使用
#     protocol            = "HTTP"
#     timeout             = 5 # タイムアウトまでの秒数
#     unhealthy_threshold = 2 # 異常判定になるまでのチェック回数
#   }
# }
#
# # ALBリスナー設定
# # クライアントからのリクエストをターゲットグループに転送するための設定
# resource "aws_lb_listener" "app" {
#   load_balancer_arn = aws_lb.main.arn
#   port              = "80" # HTTPポート
#   protocol          = "HTTP"
#
#   # デフォルトのアクション：ターゲットグループへ転送
#   default_action {
#     type             = "forward"
#     target_group_arn = aws_lb_target_group.app.arn
#   }
# }
#
# # ターゲットグループとEC2インスタンスの紐付け
# resource "aws_lb_target_group_attachment" "app" {
#   target_group_arn = aws_lb_target_group.app.arn
#   target_id        = aws_instance.dify.id # Difyアプリケーションが動作するEC2インスタンス
#   port             = 80
# }
#
# ###################################
# # Difyアプリケーション環境設定
# ###################################
# # Difyアプリケーション用セキュリティグループ
# # EC2インスタンスのトラフィックを制御
# resource "aws_security_group" "dify" {
#   name        = "${local.name_prefix}-dify-sg"
#   description = "Security group for Dify application"
#   vpc_id      = aws_vpc.main.id
#
#   # アウトバウンドルール：すべてのトラフィックを許可
#   # アプリケーションの外部接続を可能にする
#   egress {
#     from_port   = 0
#     to_port     = 0
#     protocol    = "-1"
#     cidr_blocks = ["0.0.0.0/0"]
#     description = "Allow all outbound traffic"
#   }
# }
#
# # ALBからのインバウンドトラフィックを許可するルール
# resource "aws_security_group_rule" "dify_ingress" {
#   type                     = "ingress"
#   from_port                = 80 # HTTPポート
#   to_port                  = 80
#   protocol                 = "tcp"
#   source_security_group_id = aws_security_group.alb.id # ALBからのトラフィックのみ許可
#   security_group_id        = aws_security_group.dify.id
#   description              = "Allow inbound traffic from ALB"
# }
#
# # 既存のSSHキーペアの参照
# data "aws_key_pair" "dify" {
#   key_name = "aws_id_rsa" # 事前に作成済みのSSHキーペア名
# }
#
# # Difyアプリケーション用EC2インスタンス
# resource "aws_instance" "dify" {
#   ami                    = "ami-0a290015b99140cd1"  # Amazon Linux 2 AMI ID
#   instance_type          = "t3.medium"              # インスタンスタイプ
#   subnet_id              = aws_subnet.private[0].id # プライベートサブネットに配置
#   vpc_security_group_ids = [aws_security_group.dify.id]
#   key_name               = data.aws_key_pair.dify.key_name
#   iam_instance_profile   = aws_iam_instance_profile.ssm_role.name # SSM接続用のIAMロール
#
#   # EBSルートボリューム設定
#   root_block_device {
#     volume_size           = 20    # ボリュームサイズ（GB）
#     volume_type           = "gp3" # 汎用SSD
#     delete_on_termination = true  # インスタンス削除時にボリュームも削除
#   }
#
#   # 初期セットアップスクリプト：Dockerのインストール
#   user_data = <<-EOF
#     #!/bin/bash
#     # Docker のインストール
#     sudo curl -fsSL https://get.docker.com -o get-docker.sh
#     sudo sh get-docker.sh
#
#     # PostgreSQL クライアントのインストール
#     sudo apt install -y postgresql-client
#
#     # redis-tools のインストール
#     sudo apt install -y redis-tools
#
#     # Dify のインストール
#     sudo git clone https://github.com/langgenius/dify.git
#     cd /dify/docker
#     sudo cp .env.example .env
#     sudo docker compose up -d
#   EOF
# }
#
# ###################################
# # IAMロール設定
# ###################################
# # Systems Manager（SSM）接続用のIAMロールポリシー
# data "aws_iam_policy_document" "ssm_role" {
#   statement {
#     actions = ["sts:AssumeRole"]
#     principals {
#       type        = "Service"
#       identifiers = ["ec2.amazonaws.com"]
#     }
#   }
# }
#
# # SSM接続用のIAMロール作成
# resource "aws_iam_role" "ssm_role" {
#   name               = "${local.name_prefix}-ssm-role"
#   assume_role_policy = data.aws_iam_policy_document.ssm_role.json
# }
#
# # EC2インスタンス用のIAMインスタンスプロファイル
# resource "aws_iam_instance_profile" "ssm_role" {
#   name = "${local.name_prefix}-ssm-instance-profile"
#   role = aws_iam_role.ssm_role.name
# }
#
# # SSM管理に必要なポリシーをロールにアタッチ
# resource "aws_iam_role_policy_attachment" "ssm_role" {
#   role       = aws_iam_role.ssm_role.name
#   policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore" # AWS管理ポリシー
# }
#
#
# ###################################
# # Aurora PostgreSQL Serverless v2
# ###################################
#
# # Auroraクラスターの作成
# resource "aws_rds_cluster" "aurora_postgres" {
#   cluster_identifier     = "${local.name_prefix}-aurora-cluster"
#   engine                 = "aurora-postgresql"                         # Aurora PostgreSQL を選択
#   engine_mode            = "provisioned"                               # Serverless v2に対応するモード
#   engine_version         = "15.3"                                      # Aurora PostgreSQLのバージョン
#   database_name          = "dify"                                      # デフォルトのデータベース名
#   master_username        = "dify_admin"                                # 管理者ユーザー名
#   master_password        = random_password.aurora_master.result        # 管理者パスワード
#   vpc_security_group_ids = [aws_security_group.aurora.id]              # 使用するセキュリティグループ
#   db_subnet_group_name   = aws_db_subnet_group.aurora.name             # 使用するサブネットグループ
#
#   # Serverless v2 のスケーリング設定
#   serverlessv2_scaling_configuration {
#     min_capacity = 0.5 # 最小ACU (Aurora Capacity Unit)
#     max_capacity = 16  # 最大ACU
#   }
#
#   skip_final_snapshot = true # 削除時にスナップショットを作成しない
# }
#
# # Auroraクラスターのインスタンス作成
# resource "aws_rds_cluster_instance" "aurora_postgres_instance" {
#   identifier         = "${local.name_prefix}-aurora-instance"
#   cluster_identifier = aws_rds_cluster.aurora_postgres.id
#   instance_class     = "db.serverless"                                # Serverlessインスタンスクラス
#   engine_version     = aws_rds_cluster.aurora_postgres.engine_version # 同じエンジンバージョンを使用
#   engine             = aws_rds_cluster.aurora_postgres.engine
# }
#
# # Aurora管理者パスワードを生成
# resource "random_password" "aurora_master" {
#   length  = 16   # 生成するパスワードの長さ
#   special = true # 特殊文字を含める
# }
#
# # Aurora用のセキュリティグループ
# resource "aws_security_group" "aurora" {
#   name        = "${local.name_prefix}-aurora-sg"
#   description = "Security group for Aurora PostgreSQL Cluster"
#   vpc_id      = aws_vpc.main.id
#
#   # すべてのアウトバウンドトラフィックを許可
#   egress {
#     from_port   = 0
#     to_port     = 0
#     protocol    = "-1"
#     cidr_blocks = ["0.0.0.0/0"]
#   }
# }
#
# # DifyアプリケーションからAuroraへのアクセスを許可
# resource "aws_security_group_rule" "aurora_access" {
#   type                     = "ingress"
#   from_port                = 5432 # PostgreSQLのデフォルトポート
#   to_port                  = 5432
#   protocol                 = "tcp"
#   source_security_group_id = aws_security_group.dify.id # Difyアプリケーションのセキュリティグループからの接続を許可
#   security_group_id        = aws_security_group.aurora.id
#   description              = "Allow database access from Dify application"
# }
#
# # Aurora用のサブネットグループ
# resource "aws_db_subnet_group" "aurora" {
#   name        = "${local.name_prefix}-aurora-subnet-group"
#   subnet_ids  = aws_subnet.private[*].id # プライベートサブネットで構成
#   description = "Subnet group for Aurora PostgreSQL"
# }
#
#
# ###################################
# # ElastiCache for Redis Serverless
# ###################################
#
# # ElastiCacheのセキュリティグループ
# resource "aws_security_group" "elasticache" {
#   name        = "${local.name_prefix}-elasticache-sg"
#   description = "Security group for ElastiCache Redis Cluster"
#   vpc_id      = aws_vpc.main.id
#
#   # すべてのアウトバウンドトラフィックを許可
#   egress {
#     from_port = 0
#     to_port   = 0
#     protocol  = "-1"
#     cidr_blocks = ["0.0.0.0/0"]
#   }
# }
#
# # DifyアプリケーションからElastiCacheへのアクセスを許可
# resource "aws_security_group_rule" "elasticache_access" {
#   type              = "ingress"
#   from_port = 6379 # Redisのデフォルトポート
#   to_port           = 6379
#   protocol          = "tcp"
#   source_security_group_id = aws_security_group.dify.id # Difyアプリケーションのセキュリティグループからの接続を許可
#   security_group_id = aws_security_group.elasticache.id
#   description       = "Allow Redis access from Dify application"
# }
#
# # ElastiCache for Redis Serverless
# resource "aws_elasticache_serverless_cache" "dify" {
#   engine = "redis"
#   name   = "dify"
#   cache_usage_limits {
#     data_storage {
#       maximum = 10
#       unit    = "GB"
#     }
#     ecpu_per_second {
#       maximum = 5000
#     }
#   }
#   daily_snapshot_time      = "09:00"
#   description              = "Test Server"
#   major_engine_version     = "7"
#   snapshot_retention_limit = 1
#   security_group_ids       = [aws_security_group.elasticache.id]
#   subnet_ids               = aws_subnet.private[*].id
# }