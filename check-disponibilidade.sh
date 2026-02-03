url="https://bia-aws.jar-ti.click"
docker build -t check_disponibilidade -f Dockerfile_checkdisponibilidade .
docker run --rm -ti -e URL=$url check_disponibilidade
