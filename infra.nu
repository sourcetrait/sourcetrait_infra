#!/usr/bin/env nu

export const BUILDS: list<path> = [
  'lab/ad/kvm/controller'
  'lab/ad/kvm/member'
]

export def builds []: nothing -> list<path> { BUILDS }

export def 'main build' [build: path@builds, name: string] {
  if not ($build in $BUILDS) {
    error make $"not a build"
  }

  match $build {
    'lab/ad/kvm/member' => {
        overlay use --prefix ./lab/ad/kvm/member 
        member build $name
        overlay hide member
    },
    _ => {},
  }
}

# do stuff
export def main [] { help infra }
