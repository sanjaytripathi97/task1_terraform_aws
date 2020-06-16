provider "aws" {
    profile = "default"
    region = "ap-south-1"
                          }
/* ----------------------------------------------------------*/
resource "aws_security_group" "ssh_http" {
  name        = "webserver"
  description = "Allow webserver Traffic"
  vpc_id      = "vpc-43968a2b"

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
                                }

  ingress {
    description = "TLS from VPC"
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
    Name = "TerraformSecurity"
                                }
}
/* ----------------------------------------------------------*/


/* key generating */
/* ----------------------------------------------------------*/
resource "tls_private_key" "sanjaykey" {
  algorithm   = "RSA"
  
}

resource "aws_key_pair" "public_key" {
  depends_on = [ tls_private_key.sanjaykey  ]
  key_name   = "sanjaykey"
  public_key = tls_private_key.sanjaykey.public_key_openssh
}

/* for printing private key */
/*output "key_output" { 
        value = tls_private_key.sanjaykey  
} */

/* for saving key in local file for further use */

resource "local_file" "key_saving" {
    content     = tls_private_key.sanjaykey.private_key_pem
    filename = "sanjaykey.pem"
    file_permission = "0400"
}

/* ---------------------------------------------------------------*/

/*making instance,volume,attaching volume,installing s/w */
/* ----------------------------------------------------------*/

resource "aws_instance" "os1" {
  depends_on = [ 
        local_file.key_saving 
                             ]
  ami           = "ami-0447a12f28fddb066"
  instance_type = "t2.micro"
  security_groups = [ "webserver" ]
  key_name = "sanjaykey"

  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.sanjaykey.private_key_pem
    host     = aws_instance.os1.public_ip
                                         }
  

  provisioner "remote-exec" {
    inline = [
      "sudo yum install httpd php git -y",
      "sudo systemctl start httpd",
      "sudo systemctl enable httpd"
                                 ]
                                  }

  tags = {
    Name = "webserver"
                      }
}

resource "aws_ebs_volume" "ebs_os1" {
  availability_zone = aws_instance.os1.availability_zone
  size              = 1

  tags = {
    Name = "os1ebs"
                   }
}

resource "aws_volume_attachment" "ebs_attach_webserver" {
  depends_on = [ aws_ebs_volume.ebs_os1 ]
  device_name = "/dev/sdh"
  volume_id   = aws_ebs_volume.ebs_os1.id
  instance_id = aws_instance.os1.id
  force_detach = true
}

/*output "myos1_ip" {
    value = aws_instance.os1
} */

resource "null_resource" "filepublic_ip_save" {
         provisioner "local-exec" {
           command = "echo ${aws_instance.os1.public_ip} > public.txt"
                                                                     }
}

resource "null_resource" "mountssh" {
  depends_on = [
    aws_volume_attachment.ebs_attach_webserver
                                              ] 
   connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.sanjaykey.private_key_pem
    host     = aws_instance.os1.public_ip
                                         }
  

  provisioner "remote-exec" {
    inline = [
      "sudo mkfs.ext4 /dev/xvdh",
      "sudo mount /dev/xvdh /var/www/html/",
      "sudo rm -rf /var/www/html/*",
      "sudo git clone https://github.com/sanjaytripathi97/terraform_code.git /var/www/html/"
             ] 
               }
}

/*-------------------------------------------------------------------*/

/* creating s3_bucket */
/*-------------------------------------------------------------------*/
resource "aws_s3_bucket" "stbucket" {
  bucket = "sanjayt874"
  acl    = "public-read"
  region = "ap-south-1"
  
    versioning {
    enabled = true
                  }
  tags = {
    Name        = "myimagesbucket"
    Environment = "Development"
                               }
}
  
/*output "s3out" {
      value = aws_s3_bucket.stbucket
}
output "s3out_bucket_name" {
      value = aws_s3_bucket.stbucket.bucket
}*/

/*uploading content to s3 bucket*/ 

resource "aws_s3_bucket_object" "data_to_s3" {
    depends_on = [ 
          aws_s3_bucket.stbucket 
                                 ]
    bucket  = aws_s3_bucket.stbucket.bucket
    key     = "taj.jpeg"
    source  = "taj.jpg"
    acl     = "public-read"
}

/*output "s3out_bucket_data" {
      value = aws_s3_bucket_object.data_to_s3
}*/

/*------------------------------------------------------------------*/

/*-----------cloudFront-------------*/

resource "aws_cloudfront_distribution" "s3_distribution" {
  depends_on = [
       aws_s3_bucket_object.data_to_s3
                                 ]
  origin {
    domain_name = aws_s3_bucket.stbucket.bucket_domain_name
    origin_id   = "S3_web_ec2"
                              }
    enabled     = true
  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3_web_ec2"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
                       }
                            }

    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
                              }
                                 }

  tags = {
    Environment = "production"
                              }

  viewer_certificate {
    cloudfront_default_certificate = true
                                         }
}

//*output "cloud_front_output" {
  //    value = aws_cloudfront_distribution.s3_distribution
//}*/
/*-------------------------------------------------------------------------------------------------------*/
resource "null_resource" "cloud_front_url" {
  depends_on = [
    aws_cloudfront_distribution.s3_distribution
                                              ] 
   connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.sanjaykey.private_key_pem
    host     = aws_instance.os1.public_ip
                                         }
  

  provisioner "remote-exec" {
    inline = [
            "sudo sh -c \"echo '<img src=https://${aws_cloudfront_distribution.s3_distribution.domain_name}/taj.jpeg width=400 height=500>' >> /var/www/html/index.php\""
             ] 
               }
}

output "cloud_front_output_domain_name" {
      value = aws_cloudfront_distribution.s3_distribution.domain_name
}
/*-------------------------------------------------------------------------------------------------------*/

/*---------------------------END---------------------------*/
