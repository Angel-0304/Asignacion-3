#!/usr/bin/env bash
# =============================================================================
# install_zabbix.sh
# Instalación de Zabbix 6.0 LTS (MySQL + Apache) en Ubuntu Server 20.04
# Laboratorio: Monitoreo SNMP con Zabbix - Angel Alcantara (2024-2356) - ITLA
#
# Uso:  sudo bash install_zabbix.sh
# La contraseña de la base de datos se pide al ejecutar, no se guarda en el repo.
# =============================================================================
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Ejecuta el script como root: sudo bash $0"
  exit 1
fi

read -rsp "Contraseña para el usuario 'zabbix' de MySQL: " DB_PASS; echo

echo "[1/7] Repositorio oficial de Zabbix 6.0 LTS para Ubuntu 20.04"
# Zabbix 7.0 no tiene paquetes de servidor para Ubuntu 20.04, por eso se usa 6.0 LTS
wget -q https://repo.zabbix.com/zabbix/6.0/ubuntu/pool/main/z/zabbix-release/zabbix-release_latest_6.0+ubuntu20.04_all.deb
dpkg -i zabbix-release_latest_6.0+ubuntu20.04_all.deb
apt update

echo "[2/7] Paquetes: servidor, frontend, Apache, agente, MySQL y herramientas SNMP"
apt install -y zabbix-server-mysql zabbix-frontend-php zabbix-apache-conf \
  zabbix-sql-scripts zabbix-agent mysql-server snmp

echo "[3/7] Locale requerido por el frontend y zona horaria de RD"
locale-gen en_US.UTF-8
timedatectl set-timezone America/Santo_Domingo

echo "[4/7] Base de datos y usuario"
mysql <<SQL
CREATE DATABASE IF NOT EXISTS zabbix CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;
CREATE USER IF NOT EXISTS 'zabbix'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON zabbix.* TO 'zabbix'@'localhost';
SET GLOBAL log_bin_trust_function_creators = 1;
SQL

echo "[5/7] Importando el esquema (tarda unos minutos, no muestra salida)"
zcat /usr/share/zabbix-sql-scripts/mysql/server.sql.gz | \
  mysql --default-character-set=utf8mb4 -uzabbix -p"${DB_PASS}" zabbix
mysql -e "SET GLOBAL log_bin_trust_function_creators = 0;"
mysql -e "SELECT COUNT(*) AS tablas FROM information_schema.tables WHERE table_schema='zabbix';"

echo "[6/7] Contraseña de la BD en zabbix_server.conf"
sed -i "s/^# DBPassword=.*/DBPassword=${DB_PASS}/" /etc/zabbix/zabbix_server.conf
grep -q "^DBPassword=" /etc/zabbix/zabbix_server.conf || echo "DBPassword=${DB_PASS}" >> /etc/zabbix/zabbix_server.conf

echo "[7/7] Servicios"
# snmpd se instala como dependencia; el servidor solo consulta SNMP, así que se desactiva
systemctl disable --now snmpd || true
systemctl restart zabbix-server zabbix-agent apache2
systemctl enable zabbix-server zabbix-agent apache2
systemctl --no-pager status zabbix-server | head -n 5

echo
echo "Listo. Abre http://<IP_DEL_SERVIDOR>/zabbix y completa el asistente web."
echo "Usuario inicial: Admin  (cambia la contraseña por defecto al entrar)"
