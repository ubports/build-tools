@Library('ubports-build-tools') _

/*
 * Arguments of buildAndProvideDebianPackage():
 * - isArchIndependent: a hint that this package contains only 'Architecture:
 *   all' package(s), and thus Jenkins doesn't have to dispatch build to nodes
 *   of every architecture. Note that this will confuse BlueOcean UI, causing it
 *   to not show any progress during the 'Build binary' step. However, if
 *   needed, one can still track the progress on the classic UI.
 * - ignoredArches: a list of architectures where the package should not be
 *   built. For example, [ 'armhf' ].
 * - isHeavyPackage: a hint that this package requires a significantly more
 *   resource to build, and would benefit from building on faster nodes.
 */

buildAndProvideDebianPackage(
    /* isArchIndependent */ false,
    /* ignoredArchs */ [],
    /* isHeavyPackage */ false
)
