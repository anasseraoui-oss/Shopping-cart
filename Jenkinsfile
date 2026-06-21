/**
 * Enhanced Jenkins Pipeline - Shopping Cart DevOps
 *
 * Architecture:
 *   Jenkins (port 8082) -> ansible-network -> ansible-node1 -> shopping-cart:8070
 *
 * Key features:
 *   - Pre-flight Check : network setup, python3/curl install, SSH verification
 *   - Ansible Deploy   : verbose mode (-vvv) for detailed error traces
 *   - Health Check     : polling on port 8070 for up to 120 seconds
 *   - Auto-debugging   : post { failure } calls scripts/jenkins-diagnostics.sh
 */
pipeline {
    agent any

    environment {
        DOCKER_IMAGE    = 'anasseraoui/shopping-cart'
        DOCKER_TAG      = 'latest'
        ANSIBLE_NETWORK = 'ansible-network'
        TARGET_NODE     = 'ansible-node1'
        APP_NAME        = 'shopping-cart'
        APP_PORT        = '8070'
        MGMT_PORT       = '8071'
        HEALTH_RETRIES  = '12'   // 12 attempts
        HEALTH_INTERVAL = '10'   // x 10 seconds = 120 seconds total
        LOG_TAIL        = '50'
    }

    stages {

        stage('Git Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Compile') {
            steps {
                sh 'mvn clean compile -DskipTests=true'
            }
        }

        stage('OWASP Scan') {
            steps {
                catchError(buildResult: 'SUCCESS', stageResult: 'FAILURE') {
                    dependencyCheck additionalArguments: '''
                        --scan ./
                        --format XML
                        --format HTML
                        --out ./dependency-check-report
                    ''', odcInstallation: 'OWASP-DC'
                    dependencyCheckPublisher pattern: '**/dependency-check-report.xml'
                }
            }
        }

        stage('SonarQube Analysis') {
            steps {
                withSonarQubeEnv('sonar-server') {
                    sh '''mvn sonar:sonar \
                    -Dsonar.projectName=Shopping-cart \
                    -Dsonar.projectKey=Shopping-cart'''
                }
            }
        }

        stage('Build') {
            steps {
                sh 'mvn clean package -DskipTests=true'
            }
        }

        stage('Docker Build & Push') {
            steps {
                script {
                    withCredentials([usernamePassword(
                        credentialsId: 'docker-credentials',
                        passwordVariable: 'DOCKER_PASSWORD',
                        usernameVariable: 'DOCKER_USERNAME'
                    )]) {
                        sh 'echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin'
                        sh "docker build -t ${DOCKER_IMAGE}:${DOCKER_TAG} ."
                        sh "docker push ${DOCKER_IMAGE}:${DOCKER_TAG}"
                        sh 'docker logout'
                    }
                }
            }
        }

        stage('Pre-flight Check') {
            steps {
                script {
                    // Jenkins container ID (used to attach it to ansible-network)
                    env.JENKINS_CONTAINER = sh(script: 'hostname', returnStdout: true).trim()

                    echo '=== PRE-FLIGHT: Network + Ansible node readiness ==='

                    // 1. Ensure the shared Docker bridge network exists
                    sh """
                        docker network inspect ${ANSIBLE_NETWORK} >/dev/null 2>&1 \
                            || docker network create ${ANSIBLE_NETWORK}
                    """

                    // 2. Verify the Ansible target container is running
                    sh """
                        docker inspect ${TARGET_NODE} >/dev/null 2>&1 \
                            || { echo 'ERROR: ${TARGET_NODE} is not running. Start your lab stack first.'; exit 1; }
                    """

                    // 3. Connect Jenkins + ansible-node1 to ansible-network
                    //    This allows hostname resolution: ansible-node1, shopping-cart
                    sh """
                        docker network connect ${ANSIBLE_NETWORK} ${JENKINS_CONTAINER} 2>/dev/null || true
                        docker network connect ${ANSIBLE_NETWORK} ${TARGET_NODE} 2>/dev/null || true
                    """

                    // 4. Confirm both containers are attached to the network
                    sh """
                        echo 'Containers on ${ANSIBLE_NETWORK}:'
                        docker network inspect ${ANSIBLE_NETWORK} \
                            --format '{{range .Containers}}{{.Name}} {{end}}'
                    """

                    // 5. Install sshpass inside Jenkins (required for Ansible password auth)
                    echo 'Installing sshpass on Jenkins agent...'
                    sh """
                        docker exec -u 0 ${JENKINS_CONTAINER} sh -c '
                            if command -v apt-get >/dev/null 2>&1; then
                                apt-get update -qq && apt-get install -y -qq sshpass curl
                            elif command -v apk >/dev/null 2>&1; then
                                apk add --no-cache sshpass curl
                            fi
                        ' 2>/dev/null || true
                    """

                    // 6. Install python3 + curl on ansible-node1 if missing (Ansible requirement)
                    echo "Installing python3 + curl on ${TARGET_NODE} if missing..."
                    sh """
                        docker exec -u 0 ${TARGET_NODE} sh -c '
                            if ! command -v python3 >/dev/null 2>&1; then
                                echo "Installing python3..."
                                if command -v apt-get >/dev/null 2>&1; then
                                    apt-get update -qq && apt-get install -y -qq python3
                                elif command -v apk >/dev/null 2>&1; then
                                    apk add --no-cache python3
                                fi
                            fi
                            if ! command -v curl >/dev/null 2>&1; then
                                echo "Installing curl..."
                                if command -v apt-get >/dev/null 2>&1; then
                                    apt-get update -qq && apt-get install -y -qq curl ca-certificates
                                elif command -v apk >/dev/null 2>&1; then
                                    apk add --no-cache curl ca-certificates
                                fi
                            fi
                            echo "python3: \$(python3 --version)"
                            echo "curl:    \$(curl --version | head -1)"
                        '
                    """

                    // 7. Verify SSH connectivity over ansible-network (port 2222)
                    echo 'Verifying SSH connectivity: Jenkins -> ansible-node1:2222'
                    sh """
                        sshpass -p admin123 ssh \
                            -o StrictHostKeyChecking=no \
                            -o ConnectTimeout=10 \
                            -p 2222 ansible@${TARGET_NODE} \
                            'echo PRE_FLIGHT_OK && python3 --version && docker --version'
                    """

                    echo '=== PRE-FLIGHT PASSED ==='
                }
            }
        }

        stage('Ansible Deploy') {
            steps {
                // -vvv : verbose Ansible output for easier debugging in Jenkins console
                ansiblePlaybook(
                    playbook: 'ansible/deploy.yml',
                    inventory: 'inventory.ini',
                    become: false,
                    colorized: true,
                    extras: '-vvv -e docker_image=${DOCKER_IMAGE}:${DOCKER_TAG}'
                )
            }
        }

        stage('Health Check') {
            steps {
                script {
                    def maxAttempts = env.HEALTH_RETRIES.toInteger()
                    def intervalSec = env.HEALTH_INTERVAL.toInteger()
                    def isReady     = false
                    def lastStatus  = '000'
                    def lastUrl     = 'none'

                    echo "Polling port ${APP_PORT} for up to ${maxAttempts * intervalSec}s..."

                    for (int i = 0; i < maxAttempts; i++) {
                        if (i > 0) {
                            sleep intervalSec
                        }

                        // Probe port 8070 via Docker network DNS and localhost fallback.
                        // 200 = OK, 401 = Spring Security active (app is UP), 302 = redirect (app is UP)
                        def result = sh(
                            script: """
                                docker exec ${TARGET_NODE} sh -c "
                                  for endpoint in \
                                    http://${APP_NAME}:${APP_PORT}/home \
                                    http://${APP_NAME}:${APP_PORT}/health \
                                    http://localhost:${APP_PORT}/home \
                                    http://localhost:${APP_PORT}/health
                                  do
                                    code=\\\$(curl -s -L --connect-timeout 5 --max-time 10 \
                                      -o /dev/null -w '%{http_code}' \\\$endpoint 2>/dev/null || echo 000)
                                    echo \\\"  probe \\\$endpoint -> HTTP \\\$code\\\"
                                    case \\\"\\\$code\\\" in
                                      200|401|302) echo \\\"\\\$code|\\\$endpoint\\\"; exit 0 ;;
                                    esac
                                  done
                                  echo 000|none
                                " || true
                            """,
                            returnStdout: true
                        ).trim()

                        def lastLine = result.readLines().last()
                        def parts    = lastLine.tokenize('|')
                        lastStatus   = parts[0]
                        lastUrl      = parts.size() > 1 ? parts[1] : 'unknown'

                        echo "Attempt ${i + 1}/${maxAttempts} - HTTP ${lastStatus} on ${lastUrl}"

                        if (lastStatus in ['200', '401', '302']) {
                            isReady = true
                            echo "Application is UP on port ${APP_PORT} (HTTP ${lastStatus})."
                            break
                        }
                    }

                    if (!isReady) {
                        echo 'Health Check failed after 120s. Running diagnostics...'
                        sh 'chmod +x scripts/jenkins-diagnostics.sh && scripts/jenkins-diagnostics.sh'
                        error "Application unreachable on port ${APP_PORT} after 120s (last HTTP ${lastStatus})"
                    }
                }
            }
        }

        stage('Metrics Check') {
            steps {
                script {
                    def metricsStatus = sh(
                        script: """
                            docker exec ${TARGET_NODE} curl -s -o /dev/null -w '%{http_code}' \
                                http://${APP_NAME}:${MGMT_PORT}/prometheus 2>/dev/null || echo 000
                        """,
                        returnStdout: true
                    ).trim()
                    echo "Prometheus metrics HTTP status on port ${MGMT_PORT}: ${metricsStatus}"
                }
            }
        }
    }

    post {
        success {
            echo 'Pipeline completed successfully.'
        }
        failure {
            script {
                // Auto-debugging: dump container logs and network state on ANY failure
                echo '=== PIPELINE FAILED - Running auto-diagnostics ==='
                try {
                    sh 'chmod +x scripts/jenkins-diagnostics.sh && scripts/jenkins-diagnostics.sh'
                } catch (Exception e) {
                    echo "Diagnostics skipped (early-stage failure): ${e.message}"
                }
            }
        }
        always {
            echo 'Pipeline finished.'
        }
    }
}
