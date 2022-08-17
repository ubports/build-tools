def call(Boolean isArchIndependent = false, List ignoredArchs = []) {
  String stashFileList = '*.gz,*.bz2,*.xz,*.deb,*.ddeb,*.udeb,*.dsc,*.changes,*.buildinfo,lintian.txt'
  String archiveFileList = '*.gz,*.bz2,*.xz,*.deb,*.ddeb,*.udeb,*.dsc,*.changes,*.buildinfo'
  def productionBranches = [
    'master', 'main', 'ubports/latest',
    'xenial', 'ubports/xenial',
    'xenial_-_android9', 'ubports/xenial_-_android9',
    'ubports/xenial_-_edge', 'xenial_-_edge',
    'xenial_-_edge_-_android9', 'xenial_-_edge_-_pine', 'xenial_-_edge_-_wayland'
  ]
  pipeline {
    agent none
    options {
      // Only 'Build source' stage requires checkout.
      skipDefaultCheckout()
    }
    stages {
      stage('Build source') {
        agent { label 'amd64' }
        steps {
          deleteDir()
          dir('source') {
            checkout scm
          }
          sh 'SKIP_MOVE=true /usr/bin/build-source.sh'
          stash(name: 'source', includes: stashFileList)
        }
        post {
          cleanup {
            deleteDir() /* clean up our workspace */
          }
        }
      }
      stage('Build binaries') {
        parallel {
          stage('Build binary - armhf') {
            agent { label 'arm64' }
            when { expression { return !isArchIndependent && !ignoredArchs.contains('armhf') } }
            steps {
              deleteDir()
              unstash 'source'
              sh 'architecture="armhf" build-binary.sh'
              stash(includes: stashFileList, name: 'build-armhf')
            }
            post {
              cleanup {
                deleteDir() /* clean up our workspace */
              }
            }
          }
          stage('Build binary - arm64') {
            agent { label 'arm64' }
            when { expression { return !isArchIndependent && !ignoredArchs.contains('arm64') } }
            steps {
              deleteDir()
              unstash 'source'
              sh 'architecture="arm64" build-binary.sh'
              stash(includes: stashFileList, name: 'build-arm64')
            }
            post {
              cleanup {
                deleteDir() /* clean up our workspace */
              }
            }
          }
          stage('Build binary - amd64') {
            agent { label 'amd64' }
            // Always run; arch-independent packages are built here.
            steps {
              deleteDir()
              unstash 'source'
              sh 'architecture="amd64" build-binary.sh'
              stash(includes: stashFileList, name: 'build-amd64')
            }
            post {
              cleanup {
                deleteDir() /* clean up our workspace */
              }
            }
          }
        }
      }
      stage('Results') {
        agent { label 'amd64' }
        steps {
          deleteDir()
          unstash 'build-amd64'
          // If statement can only be evaluated under a script stage.
          script {
            if (!isArchIndependent) {
              if (!ignoredArchs.contains('arm64')) {
                unstash 'build-arm64'
              }
              if (!ignoredArchs.contains('armhf')) {
                unstash 'build-armhf'
              }
            }
          }
          archiveArtifacts(artifacts: archiveFileList, fingerprint: true, onlyIfSuccessful: true)
          sh '''/usr/bin/build-repo.sh'''
        }
        post {
          cleanup {
            deleteDir() /* clean up our workspace */
          }
        }
      }
    }
    post {
      always {
        node('master') {
          script {
            if (env.BRANCH_NAME in productionBranches) {
              notifyBuildStatus(
                currentBuild,
                /* jobDescription */ "DEB build of ${JOB_NAME}",
                /* jobUrl */ env.JOB_URL
              );
            }
          }
        }
      }
    }
  }
}
