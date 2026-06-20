pipeline {
    agent any
    tools {
        jdk 'jdk-11'
        maven 'maven3'
        ansible 'ansible'
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
        stage('Ansible Preparation') {
            steps {
                script {
                    // Connexion au réseau et Préparation Python
                    echo "🔗 Connecting Jenkins container to ansible-network..."
                    sh "docker network connect ansible-network \$(hostname) || true"
                    echo "🔑 Installing sshpass on Jenkins container for Ansible password auth..."
                    sh "docker exec -u 0 \$(hostname) sh -c 'apt-get update && apt-get install -y sshpass' || true"
                    echo "🐍 Installing python3 on target node (ansible-node1) for Ansible..."
                    sh "docker exec -u 0 ansible-node1 sh -c 'apt-get update && apt-get install -y python3 || apk add --no-cache python3'"
                }
            }
        }
        stage('Ansible Deploy') {
            steps {
                ansiblePlaybook(
                    playbook: 'ansible/deploy.yml',
                    inventory: 'inventory.ini',
                    become: false,
                    colorized: true
                )
            }
        }
        stage('Health Check') {
            steps {
                script {
                    echo '⏳ Attente du démarrage de Spring Boot (Polling sur 100s)...'
                    def isReady = false
                    for (int i = 0; i < 10; i++) {
                        sleep(10)
                        def status = sh(
                            script: "docker exec ansible-node1 curl -s -L -o /dev/null -w '%{http_code}' http://shopping-cart:8070/health || echo '000'",
                            returnStdout: true
                        ).trim()
                        echo "📊 Tentative ${i+1}/10 - Code HTTP : ${status}"
                        if (status == '200') { 
                            isReady = true
                            echo '✅ Health Check réussi ! L\'application est joignable.'
                            break 
                        }
                    }
                    if (!isReady) {
                        echo '❌ Health Check échoué. Récupération des logs du conteneur :'
                        sh "docker exec ansible-node1 docker logs shopping-cart"
                        error "Application unreachable after 100s"
                    }
                }
            }
        }
        stage('Metrics Check') {
            steps {
                script {
                    echo '📈 Vérification des métriques Prometheus...'
                    def metricsStatus = sh(
                        script: "docker exec ansible-node1 curl -s -o /dev/null -w '%{http_code}' http://localhost:8071/prometheus || echo 'FAILED'",
                        returnStdout: true
                    ).trim()
                    echo "📊 Code HTTP métriques : ${metricsStatus}"
                    if (metricsStatus != '200') {
                        echo "⚠️ Métriques non accessibles sur port 8071 (Code: ${metricsStatus}) - vérification sur port 8070..."
                        sh "docker exec ansible-node1 curl -s http://localhost:8070/prometheus || true"
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
