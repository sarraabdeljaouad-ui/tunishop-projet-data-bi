# TuniShop - image Airflow
# Part de l'image officielle Apache Airflow 3.3.2 et ajoute le fournisseur
# Microsoft SQL Server (pilote pymssql), pour qu'Airflow puisse parler à SQL Server Agent.
FROM apache/airflow:3.3.2

COPY requirements.txt /requirements.txt

# On réinstalle la même version d'Airflow pour que pip ne la change jamais en installant le reste.
RUN pip install --no-cache-dir "apache-airflow==${AIRFLOW_VERSION}" -r /requirements.txt
