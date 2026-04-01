FROM mcr.microsoft.com/devcontainers/base:ubuntu

USER vscode

COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/

# Install AWS CLI
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip \
    && unzip /tmp/awscliv2.zip -d /tmp \
    && /tmp/aws/install -i ~/.local/aws-cli -b ~/.local/bin\
    && rm -rf /tmp/aws /tmp/awscliv2.zip

# Install pre-commit
RUN uv tool install pre-commit

# Install Terraform and related tools
COPY --from=hashicorp/terraform:latest /bin/terraform /usr/local/bin/

# Install TFLint
COPY --from=ghcr.io/terraform-linters/tflint:latest /usr/local/bin/tflint /usr/local/bin/

# Install Trivy
COPY --from=aquasec/trivy:0.69.3 /usr/local/bin/trivy /usr/local/bin/

# Install Terraform-docs
COPY --from=quay.io/terraform-docs/terraform-docs:latest /usr/local/bin/terraform-docs /usr/local/bin/

# Install infracost
COPY --from=infracost/infracost:latest /usr/bin/infracost /usr/local/bin/