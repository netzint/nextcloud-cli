#!/bin/bash

# Deinstalliere container-manager, falls bereits installiert
echo "Deinstalliere container-manager..."
pip3 uninstall -y container-manager

# Installiere oder aktualisiere setuptools und wheel
echo "Installiere/aktualisiere setuptools und wheel..."
pip3 install --upgrade setuptools wheel

# Erstelle das .whl-Paket
echo "Erstelle das .whl-Paket..."
python3 setup.py sdist bdist_wheel


# Installiere das gewünschte .whl-Paket
echo "Installiere das .whl-Paket..."
pip3 install dist/container_manager-0.1.0-py3-none-any.whl

echo "Build abgeschlossen!"
