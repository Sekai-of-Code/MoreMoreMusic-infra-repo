#!/bin/bash

# MoreMoreMusic Deployment Script
# Usage: ./deploy.sh [dev|staging|prod] [dry-run]

set -euo pipefail

# Configuration
NAMESPACE_PREFIX="moremoremusic"
CHART_PATH="./helm/moremoremusic"
RELEASE_NAME="moremoremusic"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}" >&2
}

warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}"
}

usage() {
    echo "Usage: $0 [environment] [options]"
    echo ""
    echo "Environments:"
    echo "  dev       Deploy to development environment"
    echo "  staging   Deploy to staging environment"
    echo "  prod      Deploy to production environment"
    echo ""
    echo "Options:"
    echo "  dry-run   Show what would be deployed without actually deploying"
    echo "  --help    Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 dev                    # Deploy to development"
    echo "  $0 prod dry-run          # Dry run for production"
    echo "  $0 staging               # Deploy to staging"
}

check_dependencies() {
    log "Checking dependencies..."
    
    if ! command -v helm &> /dev/null; then
        error "Helm is not installed. Please install Helm 3.x"
        exit 1
    fi
    
    if ! command -v kubectl &> /dev/null; then
        error "kubectl is not installed. Please install kubectl"
        exit 1
    fi
    
    # Check Helm version
    HELM_VERSION=$(helm version --short | cut -d'+' -f1 | sed 's/v//')
    if [[ "$(printf '%s\n' "3.0.0" "$HELM_VERSION" | sort -V | head -n1)" != "3.0.0" ]]; then
        error "Helm version 3.x is required. Current version: $HELM_VERSION"
        exit 1
    fi
    
    success "All dependencies are installed"
}

validate_environment() {
    local env=$1
    case $env in
        dev|staging|prod)
            return 0
            ;;
        *)
            error "Invalid environment: $env"
            usage
            exit 1
            ;;
    esac
}

setup_namespace() {
    local env=$1
    local namespace="${NAMESPACE_PREFIX}-${env}"
    
    log "Setting up namespace: $namespace"
    
    if ! kubectl get namespace "$namespace" &> /dev/null; then
        log "Creating namespace: $namespace"
        kubectl create namespace "$namespace"
    else
        log "Namespace $namespace already exists"
    fi
}

validate_secrets() {
    local env=$1
    local values_file="values-${env}.yaml"
    
    log "Validating secrets configuration..."
    
    if [[ ! -f "$CHART_PATH/$values_file" ]]; then
        error "Values file not found: $values_file"
        exit 1
    fi
    
    # Check if secrets are properly configured (this is a basic check)
    warning "Please ensure all secrets are properly configured in external secret management"
    warning "This script does not validate actual secret values for security reasons"
}

lint_chart() {
    log "Linting Helm chart..."
    
    if ! helm lint "$CHART_PATH"; then
        error "Helm chart linting failed"
        exit 1
    fi
    
    success "Helm chart linting passed"
}

deploy() {
    local env=$1
    local dry_run=$2
    local namespace="${NAMESPACE_PREFIX}-${env}"
    local values_file="values-${env}.yaml"
    local release_name="${RELEASE_NAME}-${env}"
    
    log "Deploying MoreMoreMusic to $env environment..."
    log "Namespace: $namespace"
    log "Values file: $values_file"
    log "Dry run: $dry_run"
    
    # Build Helm command
    local helm_cmd="helm upgrade --install $release_name $CHART_PATH"
    helm_cmd+=" --namespace $namespace"
    helm_cmd+=" --create-namespace"
    helm_cmd+=" --values $CHART_PATH/$values_file"
    helm_cmd+=" --timeout 10m"
    
    if [[ "$dry_run" == "true" ]]; then
        helm_cmd+=" --dry-run --debug"
        log "Running dry-run deployment..."
    else
        helm_cmd+=" --wait --wait-for-jobs"
        log "Running actual deployment..."
    fi
    
    # Add dependency update
    log "Updating Helm dependencies..."
    helm dependency update "$CHART_PATH"
    
    # Execute deployment
    log "Executing: $helm_cmd"
    if eval "$helm_cmd"; then
        if [[ "$dry_run" == "true" ]]; then
            success "Dry-run completed successfully"
        else
            success "Deployment completed successfully"
            
            # Show deployment status
            log "Checking deployment status..."
            kubectl get pods -n "$namespace"
            kubectl get services -n "$namespace"
            kubectl get ingress -n "$namespace"
        fi
    else
        error "Deployment failed"
        exit 1
    fi
}

rollback() {
    local env=$1
    local namespace="${NAMESPACE_PREFIX}-${env}"
    local release_name="${RELEASE_NAME}-${env}"
    
    warning "Rolling back deployment..."
    
    if helm rollback "$release_name" --namespace "$namespace"; then
        success "Rollback completed successfully"
    else
        error "Rollback failed"
        exit 1
    fi
}

main() {
    local env=""
    local dry_run="false"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help|-h)
                usage
                exit 0
                ;;
            dry-run)
                dry_run="true"
                shift
                ;;
            rollback)
                if [[ -z "$env" ]]; then
                    error "Environment must be specified before rollback"
                    exit 1
                fi
                rollback "$env"
                exit 0
                ;;
            dev|staging|prod)
                env=$1
                shift
                ;;
            *)
                error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    # Validate environment
    if [[ -z "$env" ]]; then
        error "Environment must be specified"
        usage
        exit 1
    fi
    
    validate_environment "$env"
    
    # Change to script directory
    cd "$(dirname "$0")/.."
    
    # Run deployment pipeline
    check_dependencies
    lint_chart
    validate_secrets "$env"
    setup_namespace "$env"
    deploy "$env" "$dry_run"
}

# Handle script interruption
trap 'error "Script interrupted"; exit 1' INT TERM

# Run main function
main "$@"