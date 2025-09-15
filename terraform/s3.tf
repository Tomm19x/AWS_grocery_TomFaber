resource "random_id" "seed" {
  byte_length = 4
}

resource "aws_s3_bucket" "seed" {
  bucket = "${var.seed_bucket_prefix}-${random_id.seed.hex}"
}

# Uploading SQL-Datei from local repository
resource "aws_s3_object" "seed_sql" {
  bucket = aws_s3_bucket.seed.id
  key    = "sqlite_dump_clean.sql"
  source = "${path.root}/../backend/app/sqlite_dump_clean.sql"
  etag   = filemd5("${path.root}/../backend/app/sqlite_dump_clean.sql")
}
