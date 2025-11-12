# MoreMoreMusic Infrastructure - Claude Instructions

## Project Context
MoreMoreMusic is an **otaku-focused music streaming platform** using microservices architecture. This repository manages infrastructure provisioning, deployment configurations, and operational tools for the platform.

**Current Phase**: Infrastructure design & setup for planned microservices

## Infrastructure Stack
- **Container Orchestration**: Kubernetes
- **Infrastructure as Code**: Terraform
- **Message Streaming**: Apache Kafka
- **CI/CD**: ArgoCD (GitOps workflow)
- **Monitoring**: Prometheus + Grafana
- **Service Mesh**: Istio (planned)

## Infrastructure Principles
- **Infrastructure as Code**: All resources defined in version-controlled code
- **GitOps Workflow**: All deployments via ArgoCD from git commits
- **Security First**: Zero-trust networking, encrypted communication, RBAC
- **Cost Optimization**: Right-sizing resources, efficient scaling policies
- **Observability**: Comprehensive monitoring, logging, and tracing
- **Environment Parity**: Consistent dev/staging/prod configurations

## Claude Behavior Instructions

### Infrastructure Resource Creation
- Always include resource limits and requests in Kubernetes manifests
- Add appropriate labels and annotations for resource management
- Include security contexts and network policies by default
- Consider horizontal pod autoscaling for stateless services
- Add monitoring and health check endpoints to all services

### Terraform Module Guidelines
- Create reusable modules for common infrastructure patterns
- Include variable validation and comprehensive documentation
- Add outputs for resource identifiers and endpoints
- Include data sources for environment-specific configurations
- Follow naming conventions: `[service]-[environment]-[region]`

### Security Configuration
- Never commit secrets or credentials to version control
- Use Kubernetes secrets and configmaps for configuration
- Implement network policies to restrict pod-to-pod communication
- Enable RBAC with principle of least privilege
- Add security scanning for container images

### Environment Management
- Maintain separate configurations for dev/staging/prod
- Use Kustomize overlays for environment-specific customizations
- Implement blue-green or canary deployment strategies
- Include database migration strategies in deployment plans

## Common Infrastructure Commands

```bash
# Infrastructure Provisioning
terraform init                           # Initialize Terraform working directory
terraform plan -var-file="prod.tfvars"   # Preview infrastructure changes
terraform apply -var-file="prod.tfvars"  # Apply infrastructure changes
terraform destroy -var-file="dev.tfvars" # Destroy dev infrastructure

# Kubernetes Operations
kubectl apply -k k8s/overlays/staging/   # Deploy to staging environment
kubectl apply -k k8s/overlays/prod/      # Deploy to production environment
kubectl get pods -n moremoremusic        # Check pod status
kubectl logs -f deployment/music-service # View service logs
kubectl describe ingress                 # Check ingress configuration

# ArgoCD Operations
argocd app create moremoremusic          # Create ArgoCD application
argocd app sync moremoremusic            # Sync application state
argocd app diff moremoremusic            # View deployment diff

# Monitoring & Debugging
kubectl top nodes                        # Check node resource usage
kubectl top pods -n moremoremusic        # Check pod resource usage
kubectl port-forward svc/grafana 3000:80 # Access Grafana dashboard
```

## File Structure Conventions

```plaintext
/terraform/                    # Infrastructure as Code
  /modules/                    # Reusable Terraform modules
    /eks-cluster/              # Kubernetes cluster module
    /rds-postgresql/           # Database module
    /redis-cache/              # Cache module
  /environments/               # Environment-specific configs
    /dev/                      # Development environment
    /staging/                  # Staging environment  
    /prod/                     # Production environment

/k8s/                         # Kubernetes manifests
  /base/                      # Common resources (Kustomize base)
    /services/                # Service definitions
    /databases/               # Database configurations
    /monitoring/              # Monitoring stack
  /overlays/                  # Environment-specific overlays
    /dev/                     # Development overrides
    /staging/                 # Staging overrides
    /prod/                    # Production overrides

/scripts/                     # Operational scripts
  /setup/                     # Initial setup scripts
  /backup/                    # Backup utilities
  /migration/                 # Database migration scripts
```

## Infrastructure Quality Gates
- Terraform plans must be reviewed before apply
- Kubernetes manifests must pass `kubectl --dry-run=client`
- All infrastructure changes require resource quota validation
- Security scans must pass for all container images
- Load testing required for production deployments
- Backup and disaster recovery procedures documented

## Resource Management Guidelines

### Kubernetes Resource Specifications
```yaml
resources:
  requests:
    memory: "64Mi"
    cpu: "250m"
  limits:
    memory: "128Mi" 
    cpu: "500m"
```

### Scaling Policies
- **Frontend Services**: Scale based on CPU (target 70%)
- **Backend APIs**: Scale based on memory and request latency
- **Database**: Vertical scaling with read replicas
- **Cache**: Horizontal scaling with Redis Cluster

## Monitoring & Alerting

### Key Infrastructure Metrics
- Node CPU/memory utilization (alert >80%)
- Pod restart frequency (alert >5 restarts/hour)
- Persistent volume usage (alert >85% full)
- Network ingress/egress patterns
- Database connection pools and query performance

### Required Monitoring Labels
```yaml
labels:
  app.kubernetes.io/name: service-name
  app.kubernetes.io/component: api|database|cache
  app.kubernetes.io/part-of: moremoremusic
  environment: dev|staging|prod
```

## Security Configuration

### Network Policies
- Default deny all traffic between namespaces
- Explicit allow rules for required service communication
- External traffic only through designated ingress controllers
- Database access restricted to application pods only

### Secret Management
- Use Kubernetes secrets for sensitive data
- Implement secret rotation policies
- Never log secret values in application or infrastructure logs
- Use service accounts with minimal required permissions

## Cost Optimization
- Right-size resources based on actual usage metrics
- Use spot/preemptible instances for non-critical workloads
- Implement pod disruption budgets for graceful scaling
- Schedule resource-intensive jobs during off-peak hours
- Regular review of unused resources and cleanup

## Known Infrastructure Constraints
- **Music Storage**: High bandwidth requirements for streaming
- **Global CDN**: Multi-region deployment for content delivery
- **Database Scaling**: GDPR compliance for user data storage
- **Event Streaming**: Kafka cluster sizing for real-time analytics
- **Cost Management**: Budget constraints for initial deployment

---

*This file guides Claude's behavior for MoreMoreMusic infrastructure management. Focus on operational excellence and security.*