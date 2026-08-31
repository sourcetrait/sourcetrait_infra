#!/usr/bin/env nu

export const BUILDS: list<path> = [
  'lab/ad/kvm/controller'
  'lab/ad/kvm/member'
]

export def builds []: nothing -> list<path> { BUILDS }

export def 'main build' [build: path@builds] {
  if not ($build in $BUILDS) {
    error make $"not a build"
  }

  print $build
}

# do stuff
export def main [] { help infra }
