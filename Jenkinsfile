pipeline {
    agent any
    tools {
        jdk 'jdk-11'
        maven 'maven3'
    }
    environment {
        DOCKER_IMAGE = "anasseraoui/shopping-cart"
        DOCKER_TAG = "latest"
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
                dependencyCheck additionalArguments: '''
                    --scan ./
                    --format XML
                    --format HTML
                    --out ./dependency-check-report
                ''', odcInstallation: 'OWASP-DC'
                dependencyCheckPublisher pattern: '**/dependency-check-report.xml'
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
                    withDockerRegistry(credentialsId: 'docker-credentials', toolName: 'docker') {
                        sh "docker build -t ${DOCKER_IMAGE}:${DOCKER_TAG} ."
                        sh "docker push ${DOCKER_IMAGE}:${DOCKER_TAG}"
                    }
                }
            }
        }
        stage('Ansible Deploy') {
            steps {
                ansiblePlaybook(
                    playbook: 'ansible/deploy.yml',
                    inventory: 'inventory.ini',
                    credentialsId: 'ansible-ssh',
                    colorized: true
                )
            }
        }
        stage('Health Check') {
            steps {
                script {
                    echo '⏳ Attente de 30s pour laisser Spring Boot démarrer...'
                    sleep 30
                    echo '🌐 Vérification du Health Check via HTTP...'
                    def status = sh(
                        script: "curl -s -o /dev/null -w '%{http_code}' http://ansible-node1:8070/health || echo 'FAILED'",
                        returnStdout: true
                    ).trim()
                    echo "📊 Code HTTP obtenu : ${status}"
                    if (status != '200') {
                        error("❌ Health Check échoué - Code HTTP : ${status}. L'application n'est pas joignable sur ansible-node1:8070")
                    }
                    echo '✅ Health Check réussi !'
                }
            }
        }
        stage('Metrics Check') {
            steps {
                script {
                    echo '📈 Vérification des métriques Prometheus...'
                    def metricsStatus = sh(
                        script: "curl -s -o /dev/null -w '%{http_code}' http://ansible-node1:8071/prometheus || echo 'FAILED'",
                        returnStdout: true
                    ).trim()
                    echo "📊 Code HTTP métriques : ${metricsStatus}"
                    if (metricsStatus != '200') {
                        echo "⚠️ Métriques non accessibles sur port 8071 (Code: ${metricsStatus}) - vérification sur port 8070..."
                        sh "curl -f -s http://ansible-node1:8070/prometheus || true"
                    } else {
                        echo '✅ Métriques Prometheus accessibles !'
                    }
                }
            }
        }
    }
    post {
        success {
            echo 'Pipeline Jenkins + Ansible terminé avec succès !'
        }
        failure {
            echo 'Pipeline échoué !'
        }
        always {
            echo 'Pipeline terminé !'
        }
    }
}
