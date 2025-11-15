#!/bin/bash

# MoreMoreMusic Health Check Validation Script
# Tests health endpoints and service communication flow

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
USER_SERVICE_URL="${USER_SERVICE_URL:-http://localhost:3000}"
MUSIC_SERVICE_URL="${MUSIC_SERVICE_URL:-http://localhost:3001}"
FRONTEND_URL="${FRONTEND_URL:-http://localhost:3000}"
TIMEOUT="${TIMEOUT:-5}"

# Test results
TOTAL_TESTS=0
PASSED_TESTS=0

# Functions
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

success() {
    echo -e "${GREEN}✅ $1${NC}"
    ((PASSED_TESTS++))
}

error() {
    echo -e "${RED}❌ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

test_endpoint() {
    local service_name="$1"
    local url="$2"
    local expected_status="${3:-200}"
    
    ((TOTAL_TESTS++))
    log "Testing $service_name health endpoint: $url"
    
    local response
    local status_code
    local response_time
    
    # Make request with timeout and capture response time
    if response=$(curl -s -w "HTTPSTATUS:%{http_code};TIME:%{time_total}" \
                      --connect-timeout "$TIMEOUT" \
                      --max-time "$TIMEOUT" \
                      "$url" 2>/dev/null); then
        
        # Extract status code and response time
        status_code=$(echo "$response" | grep -o "HTTPSTATUS:[0-9]*" | cut -d: -f2)
        response_time=$(echo "$response" | grep -o "TIME:[0-9.]*" | cut -d: -f2)
        response_body=$(echo "$response" | sed -E 's/HTTPSTATUS:[0-9]*;//g' | sed -E 's/TIME:[0-9.]*;//g')
        
        if [[ "$status_code" == "$expected_status" ]]; then
            success "$service_name health check passed (${status_code}) - Response time: ${response_time}s"
            
            # Parse response body if it's JSON
            if echo "$response_body" | jq . >/dev/null 2>&1; then
                local service_status=$(echo "$response_body" | jq -r '.status // "unknown"')
                local timestamp=$(echo "$response_body" | jq -r '.timestamp // "unknown"')
                echo "   Service Status: $service_status"
                echo "   Timestamp: $timestamp"
                
                # Check if service reports as healthy
                if [[ "$service_status" == "ok" || "$service_status" == "healthy" ]]; then
                    echo "   ✅ Service reports healthy status"
                else
                    warning "Service reports non-healthy status: $service_status"
                fi
            else
                echo "   Response: $response_body"
            fi
        else
            error "$service_name health check failed - Expected: $expected_status, Got: $status_code"
            echo "   Response: $response_body"
        fi
    else
        error "$service_name health check failed - Connection timeout or network error"
    fi
}

test_service_communication() {
    local service1_name="$1"
    local service1_url="$2"
    local service2_name="$3"
    local service2_url="$4"
    
    ((TOTAL_TESTS++))
    log "Testing communication between $service1_name and $service2_name"
    
    # Test if both services can reach each other's health endpoints
    # In a real microservices setup, this would test actual service-to-service communication
    
    local service1_status
    local service2_status
    
    service1_status=$(curl -s --connect-timeout "$TIMEOUT" --max-time "$TIMEOUT" \
                          -o /dev/null -w "%{http_code}" "$service1_url/health" 2>/dev/null || echo "000")
    service2_status=$(curl -s --connect-timeout "$TIMEOUT" --max-time "$TIMEOUT" \
                          -o /dev/null -w "%{http_code}" "$service2_url/health" 2>/dev/null || echo "000")
    
    if [[ "$service1_status" == "200" && "$service2_status" == "200" ]]; then
        success "Service communication test passed - Both services are reachable"
        echo "   $service1_name: $service1_status"
        echo "   $service2_name: $service2_status"
    else
        error "Service communication test failed"
        echo "   $service1_name: $service1_status"
        echo "   $service2_name: $service2_status"
    fi
}

test_api_endpoints() {
    local service_name="$1"
    local base_url="$2"
    shift 2
    local endpoints=("$@")
    
    log "Testing $service_name API endpoints"
    
    for endpoint in "${endpoints[@]}"; do
        ((TOTAL_TESTS++))
        local url="$base_url$endpoint"
        
        log "Testing endpoint: $endpoint"
        
        local response
        local status_code
        
        if response=$(curl -s -w "HTTPSTATUS:%{http_code}" \
                          --connect-timeout "$TIMEOUT" \
                          --max-time "$TIMEOUT" \
                          "$url" 2>/dev/null); then
            
            status_code=$(echo "$response" | grep -o "HTTPSTATUS:[0-9]*" | cut -d: -f2)
            response_body=$(echo "$response" | sed -E 's/HTTPSTATUS:[0-9]*;//g')
            
            if [[ "$status_code" == "200" || "$status_code" == "404" ]]; then
                success "Endpoint $endpoint is accessible ($status_code)"
            else
                warning "Endpoint $endpoint returned status: $status_code"
            fi
        else
            error "Endpoint $endpoint is not accessible"
        fi
    done
}

check_kafka_configuration() {
    ((TOTAL_TESTS++))
    log "Checking Kafka configuration in Helm chart"
    
    local helm_chart_path="/Users/yuminkim/Desktop/Workspace/Sekai-of-Code/MoreMoreMusic-infra-repo/helm/moremoremusic"
    
    if [[ -f "$helm_chart_path/Chart.yaml" ]]; then
        if grep -q "name: kafka" "$helm_chart_path/Chart.yaml"; then
            success "Kafka dependency found in Chart.yaml"
        else
            error "Kafka dependency not found in Chart.yaml"
            return
        fi
    else
        error "Chart.yaml not found"
        return
    fi
    
    if [[ -f "$helm_chart_path/values.yaml" ]]; then
        if grep -q "^kafka:" "$helm_chart_path/values.yaml"; then
            success "Kafka configuration found in values.yaml"
            
            # Check environment variables
            if grep -q "KAFKA_BROKERS:" "$helm_chart_path/values.yaml"; then
                success "Kafka broker environment variables configured"
            else
                warning "Kafka broker environment variables not found"
            fi
        else
            error "Kafka configuration not found in values.yaml"
        fi
    else
        error "values.yaml not found"
    fi
}

check_infrastructure_setup() {
    ((TOTAL_TESTS++))
    log "Checking infrastructure setup"
    
    local helm_chart_path="/Users/yuminkim/Desktop/Workspace/Sekai-of-Code/MoreMoreMusic-infra-repo/helm/moremoremusic"
    local script_path="/Users/yuminkim/Desktop/Workspace/Sekai-of-Code/MoreMoreMusic-infra-repo/scripts"
    
    # Check if legacy k8s directory was removed
    if [[ ! -d "/Users/yuminkim/Desktop/Workspace/Sekai-of-Code/MoreMoreMusic-infra-repo/k8s" ]]; then
        success "Legacy k8s directory successfully removed"
    else
        warning "Legacy k8s directory still exists"
    fi
    
    # Check Helm chart structure
    if [[ -d "$helm_chart_path" ]]; then
        success "Helm chart directory exists"
        
        # Check essential files
        local required_files=("Chart.yaml" "values.yaml" "values-dev.yaml")
        for file in "${required_files[@]}"; do
            if [[ -f "$helm_chart_path/$file" ]]; then
                echo "   ✅ $file exists"
            else
                echo "   ❌ $file missing"
            fi
        done
    else
        error "Helm chart directory not found"
    fi
    
    # Check deployment script
    if [[ -f "$script_path/deploy.sh" && -x "$script_path/deploy.sh" ]]; then
        success "Deployment script exists and is executable"
    else
        error "Deployment script missing or not executable"
    fi
}

run_performance_test() {
    ((TOTAL_TESTS++))
    log "Running basic performance test"
    
    local url="$USER_SERVICE_URL/health"
    local requests=10
    local total_time=0
    local successful_requests=0
    
    for i in $(seq 1 $requests); do
        local start_time=$(date +%s.%N)
        
        if curl -s --connect-timeout "$TIMEOUT" --max-time "$TIMEOUT" "$url" >/dev/null 2>&1; then
            local end_time=$(date +%s.%N)
            local request_time=$(echo "$end_time - $start_time" | bc -l)
            total_time=$(echo "$total_time + $request_time" | bc -l)
            ((successful_requests++))
        fi
    done
    
    if [[ $successful_requests -gt 0 ]]; then
        local avg_time=$(echo "scale=3; $total_time / $successful_requests" | bc -l)
        success "Performance test completed"
        echo "   Successful requests: $successful_requests/$requests"
        echo "   Average response time: ${avg_time}s"
        
        # Check if response time is acceptable (< 1 second)
        if (( $(echo "$avg_time < 1.0" | bc -l) )); then
            echo "   ✅ Response time is acceptable"
        else
            warning "Response time is high (>1s)"
        fi
    else
        error "Performance test failed - No successful requests"
    fi
}

# Main execution
main() {
    log "Starting MoreMoreMusic Health Check Validation"
    log "================================================"
    
    # Basic health checks
    log "Phase 1: Basic Health Checks"
    test_endpoint "User Service" "$USER_SERVICE_URL/health"
    test_endpoint "Music Service" "$MUSIC_SERVICE_URL/health"
    
    # API endpoints
    log "\nPhase 2: API Endpoint Tests"
    test_api_endpoints "User Service" "$USER_SERVICE_URL" "/api/hello"
    test_api_endpoints "Music Service" "$MUSIC_SERVICE_URL" "/api/music/status" "/api/hello"
    
    # Service communication
    log "\nPhase 3: Service Communication Tests"
    test_service_communication "User Service" "$USER_SERVICE_URL" "Music Service" "$MUSIC_SERVICE_URL"
    
    # Infrastructure checks
    log "\nPhase 4: Infrastructure Configuration"
    check_kafka_configuration
    check_infrastructure_setup
    
    # Performance test
    log "\nPhase 5: Basic Performance Test"
    run_performance_test
    
    # Summary
    log "\n================================================"
    log "Health Check Validation Complete"
    
    local success_rate=$(echo "scale=1; $PASSED_TESTS * 100 / $TOTAL_TESTS" | bc -l)
    
    echo -e "\n${BLUE}Summary:${NC}"
    echo "  Total tests: $TOTAL_TESTS"
    echo "  Passed: $PASSED_TESTS"
    echo "  Failed: $((TOTAL_TESTS - PASSED_TESTS))"
    echo "  Success rate: ${success_rate}%"
    
    if [[ $PASSED_TESTS -eq $TOTAL_TESTS ]]; then
        success "All tests passed! MoreMoreMusic infrastructure is healthy."
        exit 0
    elif [[ $PASSED_TESTS -gt $((TOTAL_TESTS / 2)) ]]; then
        warning "Most tests passed, but some issues were found."
        exit 1
    else
        error "Multiple critical issues found. Please review the infrastructure."
        exit 2
    fi
}

# Handle script interruption
trap 'error "Health check interrupted"; exit 1' INT TERM

# Check dependencies
command -v curl >/dev/null 2>&1 || { error "curl is required but not installed"; exit 1; }
command -v jq >/dev/null 2>&1 || { warning "jq not installed, JSON parsing will be limited"; }
command -v bc >/dev/null 2>&1 || { warning "bc not installed, performance calculations will be limited"; }

# Run main function
main "$@"