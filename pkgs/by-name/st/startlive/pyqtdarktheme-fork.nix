# PyQtDarkTheme-fork is the maintained repackaging of PyQtDarkTheme that
# StartLive pins (`PyQtDarkTheme-fork~=2.3.6`). nixpkgs only carries the
# original `pyqtdarktheme`, which is still at 2.1.0 and predates the Python
# versions nixpkgs now ships, so the fork is built here. Both install the same
# `qdarktheme` module, and the fork's only runtime dependency is `darkdetect`.
{
  lib,
  fetchPypi,
  buildPythonPackage,
  poetry-core,
  darkdetect,
}:

buildPythonPackage (finalAttrs: {
  pname = "pyqtdarktheme-fork";
  version = "2.3.6";
  pyproject = true;

  # PyPI serves the file under the distribution's original underscore name,
  # and fetchPypi derives the file name from the `pname` it is given.
  src = fetchPypi {
    pname = "pyqtdarktheme_fork";
    inherit (finalAttrs) version;
    hash = "sha256-mrKHoDOkdCdnvLZpj7YCR77veWfXTrlJ96s27oZv8dc=";
  };

  build-system = [ poetry-core ];

  dependencies = [ darkdetect ];

  # The sdist ships no tests, and importing `qdarktheme` pulls in a Qt
  # binding, which this library deliberately does not depend on itself.
  doCheck = false;

  meta = {
    description = "Flat dark theme for PySide and PyQt (maintained fork)";
    homepage = "https://github.com/5yutan5/PyQtDarkTheme";
    license = lib.licenses.mit;
    maintainers = [ ];
  };
})
