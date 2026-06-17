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
                    sleep 15
                    sh "curl -s http://ansible-node1:8071/health | grep '\"status\":\"UP\"'"
                }
            }
        }
        stage('Metrics Check') {
            steps {
                script {
                    sh "curl -f -s http://ansible-node1:8071/prometheus"
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
