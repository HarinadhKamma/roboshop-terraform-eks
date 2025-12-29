resource "aws_ecr_repository" "catalogue" {
  name                 = "${project_name}/catalogue"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = false
  }
  force_delete = true
}

resource "aws_ecr_repository" "user" {
  name                 = "${project_name}/user"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = false
  }
  force_delete = true
}

resource "aws_ecr_repository" "cart" {
  name                 = "${project_name}/cart"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = false
  }
  force_delete = true
}

resource "aws_ecr_repository" "shipping" {
  name                 = "${project_name}/shipping"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = false
  }
  force_delete = true
}

resource "aws_ecr_repository" "payment" {
  name                 = "${project_name}/payment"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = false
  }
  force_delete = true
}

resource "aws_ecr_repository" "frontend" {
  name                 = "${project_name}/frontend"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = false
  }
  force_delete = true
}