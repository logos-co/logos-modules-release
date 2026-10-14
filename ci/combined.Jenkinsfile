#!/usr/bin/env groovy

library 'status-jenkins-lib@v1.9.51'

urls = [:]

pipeline {
  agent {
    docker {
      label 'linuxcontainer'
      image 'harbor.status.im/infra/ci-build-containers:linux-base-1.0.2'
      args '--volume=/nix:/nix ' +
           '--volume=/etc/nix:/etc/nix '
    }
  }

  options {
    timestamps()
    ansiColor('xterm')
    disableConcurrentBuilds()
    disableRestartFromStage()
    timeout(time: 180, unit: 'MINUTES')
    buildDiscarder(logRotator(
      numToKeepStr: '10',
      daysToKeepStr: '30',
      artifactNumToKeepStr: '10',
    ))
  }

  parameters {
    string(
      name: 'MODULES',
      description: 'Comma-separated submodule dir names to release. Empty = all.',
      defaultValue: params.MODULES ?: ''
    )
    booleanParam(
      name: 'SKIP_IF_PUBLISHED',
      description: 'Skip modules whose <name>-v<version> release already has .lgx + sidecar.json.',
      defaultValue: params.SKIP_IF_PUBLISHED != null ? params.SKIP_IF_PUBLISHED : true
    )
    booleanParam(
      name: 'SIGN',
      description: 'Sign packages with the release key.',
      defaultValue: params.SIGN != null ? params.SIGN : true
    )
    booleanParam(
      name: 'PUBLISH',
      description: 'Publish GitHub releases. The catalog index is rebuilt by the rebuild-index GitHub workflow on each published release.',
      defaultValue: utils.isReleaseBuild() || (params.PUBLISH ?: false)
    )
    string(
      name: 'STORAGE_NODES_TEST',
      description: 'Comma-separated logos.test storage node base URLs. Empty skips that network.',
      defaultValue: params.STORAGE_NODES_TEST ?: 'https://node-02.gc-us-central1-a.logos.test.status.im',
    )
    string(
      name: 'STORAGE_NODES_DEV',
      description: 'Comma-separated logos.dev storage node base URLs. Empty skips that network.',
      defaultValue: params.STORAGE_NODES_DEV ?: 'https://storage-02.gc-us-central1-a.logos.dev.status.im',
    )
    string(
      name: 'BRANCH',
      description: 'Git branch to build.',
      defaultValue: 'main'
    )
  }

  environment {
    GH_USER = 'logos-co'
    GH_NAME = 'logos-modules-release'
    GH_REPO = "${GH_USER}/${GH_NAME}"
  }

  stages {
    stage('Setup') {
      steps { script {
        def all = sh(
          script: "find submodules -mindepth 1 -maxdepth 1 -type d -printf '%f\\n' | sort",
          returnStdout: true
        ).trim().split('\n') as List
        def requested = params.MODULES?.trim() ?
          params.MODULES.split(',').collect { it.trim() }.findAll { it } : all
        def unknown = requested - all
        if (unknown) { error("Unknown modules: ${unknown.join(', ')}") }

        def toBuild = requested
        if (params.SKIP_IF_PUBLISHED) {
          withCredentials([usernamePassword(
            credentialsId:    'status-im-auto',
            usernameVariable: 'GITHUB_USER',
            passwordVariable: 'GH_TOKEN',
          )]) {
            def output = nix.develop(
              keepEnv: ['GH_TOKEN', 'GH_REPO'],
              returnStdout: true,
              "scripts/check-published.sh ${requested.join(' ')}"
            )
            toBuild = output.trim() ? output.trim().split('\n') as List : []
          }
        }

        if (toBuild.isEmpty()) {
          currentBuild.description = 'All requested modules already published'
        }
        env.BUILD_MODULES = toBuild.join(',')
        echo "Building: ${env.BUILD_MODULES ?: '<none>'}"
      } }
    }

    stage('Build') {
      when { expression { hasModules() } }
      parallel {
        stage('Linux/x86_64') { steps { script {
          getArtifacts('Linux', build(
            job: 'logos/logos-modules-release/systems/linux/x86_64/package',
            parameters: [
              string(name: 'MODULES', value: env.BUILD_MODULES),
              string(name: 'BRANCH',  value: params.BRANCH),
            ],
          ))
        } } }
        stage('Linux/aarch64') { steps { script {
          getArtifacts('Linux-ARM', build(
            job: 'logos/logos-modules-release/systems/linux/aarch64/package',
            parameters: [
              string(name: 'MODULES', value: env.BUILD_MODULES),
              string(name: 'BRANCH',  value: params.BRANCH),
            ],
          ))
        } } }
        stage('macOS/aarch64') { steps { script {
          getArtifacts('macOS', build(
            job: 'logos/logos-modules-release/systems/macos/aarch64/package',
            parameters: [
              string(name: 'MODULES', value: env.BUILD_MODULES),
              string(name: 'BRANCH',  value: params.BRANCH),
            ],
          ))
        } } }
      }
    }

    stage('Merge & Sign') {
      when { expression { hasModules() } }
      steps { script {
        def creds = []
        if (params.SIGN) {
          creds << file(credentialsId: 'logos-lgx-release-signing-key', variable: 'LGX_SIGNING_KEY')
        }
        if (params.STORAGE_NODES_TEST?.trim()) {
          creds << usernamePassword(
            credentialsId:    'logos-storage-node-auth-test',
            usernameVariable: 'STORAGE_USER_TEST',
            passwordVariable: 'STORAGE_PASS_TEST',
          )
        }
        if (params.STORAGE_NODES_DEV?.trim()) {
          creds << usernamePassword(
            credentialsId:    'logos-storage-node-auth-dev',
            usernameVariable: 'STORAGE_USER_DEV',
            passwordVariable: 'STORAGE_PASS_DEV',
          )
        }
        withCredentials(creds) {
          withEnv([
            "STORAGE_NODES_TEST=${params.STORAGE_NODES_TEST?.trim() ?: ''}",
            "STORAGE_NODES_DEV=${params.STORAGE_NODES_DEV?.trim() ?: ''}",
          ]) {
            def failed = []
            def modules = env.BUILD_MODULES.split(',') as List
            modules.each { m ->
              def status = nix.develop(
                keepEnv: ['LGX_SIGNING_KEY',
                          'STORAGE_NODES_TEST', 'STORAGE_USER_TEST', 'STORAGE_PASS_TEST',
                          'STORAGE_NODES_DEV',  'STORAGE_USER_DEV',  'STORAGE_PASS_DEV'],
                returnStatus: true,
                "scripts/release-module.sh ${m} pkg released"
              )
              if (status != 0) { failed << m }
            }
            if (failed) { unstable("Packaging failed for: ${failed.join(', ')}") }
            if (failed.size() == modules.size()) { error('Every module failed packaging') }
          }
        }
      } }
    }

    stage('Publish Releases') {
      when { expression { hasModules() && params.PUBLISH } }
      steps { script {
        findFiles(glob: 'released/*/TAG').each { tagFile ->
          def moddir = tagFile.path.replaceAll('/TAG$', '')
          def tag    = readFile(tagFile.path).trim()
          def files  = (findFiles(glob: "${moddir}/*.lgx") +
                        findFiles(glob: "${moddir}/sidecar.json"))*.path
          github.upsertRelease(
            user:    env.GH_USER,
            repo:    env.GH_NAME,
            version: tag,
            name:    readFile("${moddir}/TITLE").trim(),
            branch:  env.GIT_COMMIT,
            desc:    readFile("${moddir}/NOTES").trim(),
            files:   files,
          )
          echo "Published ${tag}"
        }
      } }
    }

  post {
    always { script {
      archiveArtifacts(artifacts: 'released/**, pkg/report__*', allowEmptyArchive: true)
      if (urls) { jenkins.setBuildDesc(urls) }
    } }
    cleanup {
      cleanWs(disableDeferredWipeout: true)
      dir(env.WORKSPACE_TMP) { deleteDir() }
    }
  }
}

def getArtifacts(key, childBuild) {
  jenkins.copyArts(childBuild)
  urls[key] = childBuild.absoluteUrl
  jenkins.setBuildDesc(urls)
  return childBuild
}

def hasModules() {
  return env.BUILD_MODULES != null && env.BUILD_MODULES != ''
}
