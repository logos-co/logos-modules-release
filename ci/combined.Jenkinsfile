#!/usr/bin/env groovy

library 'status-jenkins-lib@v1.9.48'

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
      description: 'Publish GitHub releases and rebuild the catalog index.',
      defaultValue: utils.isReleaseBuild() || (params.PUBLISH ?: false)
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
            toBuild = requested.findAll { m ->
              def rc = nix.develop(
                keepEnv: ['GH_TOKEN', 'GH_REPO'],
                returnStatus: true,
                "scripts/check-published.sh ${m}"
              )
              if (rc == 2) { error("Publish check errored for ${m} - aborting rather than rebuilding everything") }
              if (rc == 0) { echo "SKIP ${m} - already published" }
              return rc != 0
            }
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
      when { expression { env.BUILD_MODULES } }
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
      when { expression { env.BUILD_MODULES } }
      steps { script {
        def wrap = { Closure body ->
          if (params.SIGN) {
            withCredentials([file(credentialsId: 'logos-lgx-release-signing-key', variable: 'LGX_SIGNING_KEY')]) { body() }
          } else { body() }
        }
        wrap {
          def failed = []
          def modules = env.BUILD_MODULES.split(',') as List
          modules.each { m ->
            def status = nix.develop(
              keepEnv: ['LGX_SIGNING_KEY'],
              returnStatus: true,
              "scripts/release-module.sh ${m} pkg released"
            )
            if (status != 0) { failed << m }
          }
          if (failed) { unstable("Packaging failed for: ${failed.join(', ')}") }
          if (failed.size() == modules.size()) { error('Every module failed packaging') }
        }
      } }
    }

    stage('Publish Releases') {
      when { expression { env.BUILD_MODULES && params.PUBLISH } }
      steps { script {
        findFiles(glob: 'released/*/TAG').each { tagFile ->
          def moddir = tagFile.path.replaceAll('/TAG$', '')
          def tag    = readFile(tagFile.path).trim()
          def files  = findFiles(glob: "${moddir}/*.lgx") +
                       findFiles(glob: "${moddir}/sidecar.json")
          github.upsertRelease(
            user:    env.GH_USER,
            repo:    env.GH_NAME,
            version: tag,
            desc:    readFile("${moddir}/NOTES").trim(),
            files:   files,
          )
          echo "Published ${tag}"
        }
      } }
    }

    stage('Rebuild Index') {
      when { anyOf {
        expression { env.BUILD_MODULES }
        expression { params.PUBLISH }
      } }
      steps { script {
        def status = nix.develop(
          keepEnv: ['GH_REPO'],
          returnStatus: true,
          'scripts/rebuild-index.sh released index.json'
        )
        if (status != 0) { error('Index rebuild failed') }
        if (params.PUBLISH && fileExists('index.json') && env.BUILD_MODULES) {
          github.upsertRelease(
            user:    env.GH_USER,
            repo:    env.GH_NAME,
            version: 'index',
            desc:    'Rolling catalog index. Do not delete.',
            files:   findFiles(glob: 'index.json'),
          )
          echo 'Index published'
        } else if (fileExists('index.json')) {
          echo 'DRY RUN - index.json archived for inspection, NOT uploaded'
        }
      } }
    }
  }

  post {
    always { script {
      archiveArtifacts(artifacts: 'released/**, index.json, pkg/report__*', allowEmptyArchive: true)
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
