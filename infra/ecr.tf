resource "aws_ecr_repository" "services" {
  for_each = toset([
    "cart",
    "catalog",
    "checkout",
    "orders",
    "ui",
  ])

  name                 = "retail-store/${each.value}"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}
