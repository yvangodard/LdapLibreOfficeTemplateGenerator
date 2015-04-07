#! /bin/bash

VERSION="LdapLibreOfficeTemplateGenerator v 1.1 - 2014 - Yvan GODARD - godardyvan@gmail.com - http://goo.gl/c62RYH"
SCRIPT_DIR=$(dirname $0)
SCRIPT_NAME=$(basename $0)
SCRIPT_NAME_WITHOUT_EXT=$(echo "${SCRIPT_NAME}" | cut -f1 -d '.')
LDAP_URL=""
LDAP_DN_BASE=""
RACINE=""
OTT_MASTER_FILE=""
WITH_LDAP_BIND="no"
LDAP_ADMIN_UID=""
LDAP_ADMIN_PASS=""
LDAP_DN_USER_BRANCH="cn=users"
FILTER_ON_DOMAIN=""
DOMAIN_EMAIL=""
IP_FILTER=0
HOME_DIR=$(echo ~)
DIR_EXPORT=${HOME_DIR%/}/Library/Application\ Support/LibreOffice/4/user/template
TAG=""
HELP="no"
LOG_ACTIVE=0
USER_UID=$(whoami)
LOG=${HOME_DIR%/}/Library/logs/${SCRIPT_NAME_WITHOUT_EXT}.log
# Fichier temp
LOG_TEMP=$(mktemp /tmp/${SCRIPT_NAME_WITHOUT_EXT}.XXXXX)
TEMP_IP=$(mktemp /tmp/${SCRIPT_NAME_WITHOUT_EXT}_tempip.XXXXX)
LISTE_IP=$(mktemp /tmp/${SCRIPT_NAME_WITHOUT_EXT}_listeIP.XXXXX)
CONTENT_USER=$(mktemp /tmp/${SCRIPT_NAME_WITHOUT_EXT}_fiche.XXXXX)
CONTENT_USER_BASE=$(mktemp /tmp/${SCRIPT_NAME_WITHOUT_EXT}_fiche_decode.XXXXX)
LISTE_MAIL=$(mktemp /tmp/${SCRIPT_NAME_WITHOUT_EXT}_mail.XXXXX)
LISTE_TEL=$(mktemp /tmp/${SCRIPT_NAME_WITHOUT_EXT}_tel.XXXXX)
LISTE_MOBILE=$(mktemp /tmp/${SCRIPT_NAME_WITHOUT_EXT}_mobile.XXXXX)

help () {
	echo -e "$VERSION\n"
	echo -e "Cet outil permet de personnaliser un template LibreOffice en utilisant des informations issues d'un serveur LDAP."
	echo -e "Cet outil est placé sous la licence Creative Commons 4.0 BY NC SA."
	echo -e "\nAvertissement:"
	echo -e "Cet outil est distribué dans support ou garantie, la responsabilité de l'auteur ne pourrait être engagée en cas de dommage causé à vos données."
	echo -e "\nUtilisation:"
	echo -e "./${SCRIPT_NAME} [-h] | -s <URL Serveur LDAP> -r <DN Racine>"
	echo -e "                                      -t <template LibreOffice source>" 
	echo -e "                                      [-a <LDAP admin UID>] [-p <LDAP admin password>]"
	echo -e "                                      [-u <DN relatif branche Users>]"
	echo -e "                                      [-D <filtre domaine email>] [-d <domaine email prioritaire>]"
	echo -e "                                      [-U <UID de l'utilisateur à traiter>]"
	echo -e "                                      [-i <IP depuis lesquelles lancer le processus>]"
	echo -e "                                      [-P <chemin export>] [-t <tag des exports>]"
	echo -e "                                      [-j <log file>]"
	echo -e "\n\t-h:                                   Affiche cette aide et quitte."
	echo -e "\nParamètres obligatoires :"
	echo -e "\t-r <DN Racine> :                      DN de base de l'ensemble des entrées du LDAP (ex. : 'dc=server,dc=office,dc=com')."
	echo -e "\t-s <URL Serveur LDAP> :               URL du serveur LDAP (ex. : 'ldap://ldap.serveur.office.com')."
	echo -e "\t-t <template LibreOffice source> :    Chemin complet du fichier template OTT LibreOffice source à utiliser,"
	echo -e "\t                                      avec extension ott (ex. : '/Users/moi/templates/master_template.ott')."
	echo -e "\nParamètres optionnels :"
	echo -e "\t-a <LDAP admin UID> :                 UID de l'administrateur ou utilisateur LDAP si un Bind est nécessaire"
	echo -e "\t                                      pour consulter l'annuaire (ex. : 'diradmin')."
	echo -e "\t-p <LDAP admin password> :            Mot de passe de l'utilisateur si un Bind est nécessaire pour consulter"
	echo -e "\t                                      l'annuaire (sera demandé si absent)."
	echo -e "\t-u <DN relatif branche Users> :       DN relatif de la branche Users du LDAP"
	echo -e "\t                                      (ex. : 'cn=allusers', par défaut : '${LDAP_DN_USER_BRANCH}')"
	echo -e "\t-D <filtre domaine email> :           L'utilisation de ce paramètre permet de restreindre la processus aux utilisateurs"
	echo -e "\t                                      du LDAP disposant d'une adresse email contenant un domaine"
	echo -e "\t                                      (ex. : '-D mondomaine.fr' ou '-D @serveur.mail.domaine.fr')."
	echo -e "\t-d <domaine email prioritaire> :      Permet de n'exporter que les adresses email contenant le domaine,"
	echo -e "\t                                      (ex. : '-d mondomaine.fr' ou '-d @serveur.mail.domaine.fr')."
	echo -e "\t-U <UID de l'utilisateur à traiter> : Utilisateur à rechercher dans le LDAP pour créer un template personnalisé,"
	echo -e "\t                                      par défaut l'UID suivant est utilisé : ${USER_UID}"
	echo -e "\t-i <IP> :                             Utiliser cette option pour restreindre le lancement de la commande"
	echo -e "\t                                      uniquement depuis certaines adresse IP, séparées par le caractère '%'"
	echo -e "\t                                      (ex. : '123.123.123.123%12.34.56.789')"
	echo -e "\t-P <chemin export> :                  Chemin complet du dossier vers lequel exporter le résultat"
	echo -e "\t                                      (ex. : '~/Desktop/' ou '/var/templatesoffice/', par défaut : '${STANDARD_DIR_EXPORT}'"
	echo -e "\t-T <tag des exports> :                Tag à ajouter au début du nom de fichier du template généré pour l'identifier."	
	echo -e "\t-j <fichier Log> :                    Assure la journalisation dans un fichier de log à renseigner en paramètre."
	echo -e "\t                                      (ex. : '${LOG}')"
	echo -e "\t                                      ou utilisez 'default' (${LOG})"
}

function error () {
	# 1 Pas de connection internet
	# 2 Internet OK mais pas connecté au réseau local
	# 3 LDAP injoignable
	# 4 User inexistant
	# 5 Pas de correspondance pour ce domaine
	# 6 Fichier source modèle inexistant
	# 7 Autre erreur
	echo -e "\n*** Erreur ${1} ***"
	echo -e ${2}
	alldone ${1}
}

function alldone () {
	# Journalisation si nécessaire et redirection de la sortie standard
	[ ${1} -eq 0 ] && echo "" && echo ">>> Processus terminé OK !"
	if [ ${LOG_ACTIVE} -eq 1 ]; then
		exec 1>&6 6>&-
		[[ ! -f ${LOG} ]] && touch ${LOG}
		cat ${LOG_TEMP} >> ${LOG}
		cat ${LOG_TEMP}
	fi
	# Suppression des fichiers et répertoires temporaires
	[ -f ${LOG_TEMP} ] && rm -r ${LOG_TEMP}
	[ -f ${TEMP_IP} ] && rm -r ${TEMP_IP}
	[ -f ${CONTENT_USER} ] && rm -r ${CONTENT_USER}
	[ -f ${LISTE_MOBILE} ] && rm -r ${LISTE_MOBILE}
	[ -f ${LISTE_TEL} ] && rm -r ${LISTE_TEL}
	[ -f ${LISTE_MAIL} ] && rm -r ${LISTE_MAIL}
	[ -f ${LISTE_IP} ] && rm -r ${LISTE_IP}
	[ -f ${CONTENT_USER_BASE} ] && rm -r ${CONTENT_USER_BASE}
	[[ -d ${DIR_MODELE} ]] && rm -r ${DIR_MODELE}
	exit ${1}
}

# Fonction utilisée plus tard pour les résultats de requêtes LDAP encodées en base64
function base64decode () {
	echo ${1} | grep :: > /dev/null 2>&1
	if [ $? -eq 0 ] 
		then
		VALUE=$(echo ${1} | grep :: | awk '{print $2}' | openssl enc -base64 -d )
		ATTRIBUTE=$(echo ${1} | grep :: | awk '{print $1}' | awk 'sub( ".$", "" )' )
		echo "${ATTRIBUTE} ${VALUE}"
	else
		echo ${1}
	fi
}

# Vérification des options/paramètres du script 
optsCount=0
while getopts "hr:s:t:a:p:u:D:d:i:P:T:j:U:" OPTION
do
	case "$OPTION" in
		h)	HELP="yes"
						;;
		r)	LDAP_DN_BASE=${OPTARG}
			let optsCount=$optsCount+1
						;;
	    s) 	LDAP_URL=${OPTARG}
			let optsCount=$optsCount+1
						;;
	    t) 	OTT_MASTER_FILE=${OPTARG}
			let optsCount=$optsCount+1
						;;
		a)	LDAP_ADMIN_UID=${OPTARG}
			[[ ${LDAP_ADMIN_UID} != "" ]] && WITH_LDAP_BIND="yes"
						;;
		p)	LDAP_ADMIN_PASS=${OPTARG}
                        ;;
		u) 	LDAP_DN_USER_BRANCH=${OPTARG}
						;;
		D)	FILTER_ON_DOMAIN=${OPTARG}
                        ;;
		d)	DOMAIN_EMAIL=${OPTARG}
                        ;;
        U)	USER_UID=${OPTARG}
                        ;;
		i)	[[ ! -z ${OPTARG} ]] && echo ${OPTARG} | perl -p -e 's/%/\n/g' | perl -p -e 's/ //g' | awk '!x[$0]++' >> $LISTE_IP
			IP_FILTER=1
                        ;;
        P) [[ ! -z ${OPTARG} ]] && DIR_EXPORT=${OPTARG%/}
						;;
        T)	TAG=${OPTARG}
                        ;;
        j)	[ $OPTARG != "default" ] && LOG=${OPTARG}
			LOG_ACTIVE=1
                        ;;
	esac
done

if [[ ${optsCount} != "3" ]]
	then
        help
        error 7 "Les paramètres obligatoires n'ont pas été renseignés."
fi

if [[ ${HELP} = "yes" ]]
	then
	help
fi

if [[ ${WITH_LDAP_BIND} = "yes" ]] && [[ ${LDAP_ADMIN_PASS} = "" ]]
	then
	echo "Entrez le mot de passe LDAP pour uid=$LDAP_ADMIN_UID,$LDAP_DN_USER_BRANCH,$LDAP_DN_BASE :" 
	read -s LDAP_ADMIN_PASS
fi

# Redirection de la sortie strandard vers le fichier de log
if [ $LOG_ACTIVE -eq 1 ]; then
	echo -e "\n >>> Please wait ... >>> Merci de patienter ..."
	exec 6>&1
	exec >> ${LOG_TEMP}
fi

echo -e "\n****************************** `date` ******************************\n"
echo -e "$0 démarré..."


# Test fichier template source
EXTENSION_TEMPLATE_MASTER=$(echo "${OTT_MASTER_FILE}" | sed 's/^.*\(...$\)/\1/' | perl -p -e 's/ //g' | perl -p -e 's/\.//g')
[[ ! ${EXTENSION_TEMPLATE_MASTER} == ott ]] && error 6 "Format de fichier modèle ${OTT_MASTER_FILE} incorrect."

# Par sécurité, attendons quelques instants
sleep 5

# Testons si une connection internet est ouverte
dig +short myip.opendns.com @resolver1.opendns.com > /dev/null 2>&1
[ $? -ne 0 ] && error 1 "Non connecté à internet."

# Récupérons notre IP dans un fichier temporaire
TEST_CONNECT=$(dig +short myip.opendns.com @resolver1.opendns.com)
echo ${TEST_CONNECT} > $TEMP_IP
echo "Adresse IP actuelle :"
cat ${TEMP_IP}

# Testons si nous sommes connectés sur un réseau ayant pour IP Publique une IP autorisée
if [[ ${IP_FILTER} -ne 0 ]]; then
	IP_OK=O
	for IP in $(cat ${LISTE_IP})
	do
		TEST_GREP=$(grep -c "$IP" ${TEMP_IP})
		[ $TEST_GREP -eq 1 ] && let IP_OK=$IP_OK+1 && echo "Connecté au réseau autorisé sur l'IP publique "$(cat ${TEMP_IP})"."
	done
	[[ ${IP_OK} -eq 0 ]] && error 2 "Connecté à internet hors du réseau local."
fi

# Test connection LDAP
echo -e "\nConnecting LDAP at $LDAP_URL..."
[[ ${WITH_LDAP_BIND} = "no" ]] && LDAP_COMMAND_BEGIN="ldapsearch -LLL -H ${LDAP_URL} -x"
[[ ${WITH_LDAP_BIND} = "yes" ]] && LDAP_COMMAND_BEGIN="ldapsearch -LLL -H ${LDAP_URL} -D uid=${LDAP_ADMIN_UID},${LDAP_DN_USER_BRANCH},${LDAP_DN_BASE} -w ${LDAP_ADMIN_PASS}"

${LDAP_COMMAND_BEGIN} -b ${LDAP_DN_USER_BRANCH},${LDAP_DN_BASE} > /dev/null 2>&1
[ $? -ne 0 ] && error 3 "Problème de connexion au serveur LDAP ${LDAP_URL}.\nVérifiez vos paramètres de connexion."

# Test si l'utilisateur existe dans le ldap
[[ -z $(${LDAP_COMMAND_BEGIN} -b ${LDAP_DN_USER_BRANCH},${LDAP_DN_BASE} -x uid=${USER_UID}) ]] && error 4 "Aucune correspondance avec l'identifiant ${USER_UID} trouvé dans le LDAP ${LDAP_URL}, dans la branche '${LDAP_DN_USER_BRANCH},${LDAP_DN_BASE}'."
[[ ! ${FILTER_ON_DOMAIN} == "" ]] && [[ -z $(${LDAP_COMMAND_BEGIN} -b ${LDAP_DN_USER_BRANCH},${LDAP_DN_BASE} -x uid=${USER_UID} mail | grep ${FILTER_ON_DOMAIN}) ]] && error 5 "Aucune correspondance pour ${FILTER_ON_DOMAIN} avec l'identifiant ${USER_UID} trouvé dans le LDAP ${LDAP_URL}, dans la branche '${LDAP_DN_USER_BRANCH},${LDAP_DN_BASE}'."

# Répertoires de travail
[[ ! -f ${OTT_MASTER_FILE} ]] && error 6 "Fichier modèle ${OTT_MASTER_FILE} inexistant."
DIR_OTT=$(dirname ${OTT_MASTER_FILE})
NAME_MODELE=$(basename ${OTT_MASTER_FILE})
RACINE=$(echo "${NAME_MODELE}" | cut -f1 -d '.')
DIR_MODELE="${DIR_OTT}/${RACINE}"
[[ -d ${DIR_MODELE} ]] && rm -r ${DIR_MODELE}
mkdir -p ${DIR_MODELE}
[ $? -ne 0 ] && error 7 "Problème pour créer le répertoire '${DIR_MODELE}'."
[[ ! -d ${DIR_MODELE} ]] && error 7 "Problème pour accéder au répertoire '${DIR_MODELE}'."
[[ ! -w ${DIR_MODELE} ]] && error 7 "Problème de droits d'accès en écriture au dossier ${DIR_MODELE}'."
cd ${DIR_MODELE}
echo -e "\nUNZIP vers '${DIR_MODELE}/' :"
unzip ${OTT_MASTER_FILE}
MODELE="${DIR_MODELE}/content.xml"
META="${DIR_MODELE}/meta.xml"

# Test répertoire export
[[ ! -d ${DIR_EXPORT} ]] && mkdir -p "${DIR_EXPORT}"
[[ ! -d ${DIR_EXPORT} ]] && error 7 "Problème pour accéder au répertoire '${DIR_EXPORT}'."
[[ ! -w ${DIR_EXPORT} ]] && error 7 "Problème de droits d'accès en écriture au dossier ${DIR_EXPORT}'."

# Récupérer les variables nécessaires
${LDAP_COMMAND_BEGIN} -b ${LDAP_DN_USER_BRANCH},${LDAP_DN_BASE} -x uid=${USER_UID} givenName sn cn title telephoneNumber mobile mail initials > ${CONTENT_USER_BASE}

# Décodage des informations
OLDIFS=$IFS; IFS=$'\n'
for LINE in $(cat ${CONTENT_USER_BASE})
do
	base64decode $LINE >> ${CONTENT_USER}
done
IFS=$OLDIFS

# Récupération des données
# Nom (de famille)
# Prénom 
# Titre (fonction)
NOMCOMPLET=$(cat ${CONTENT_USER} | grep ^cn: | perl -p -e 's/cn: //g')
NOM=$(cat ${CONTENT_USER} | grep ^sn: | perl -p -e 's/sn: //g')
PRENOM=$(cat ${CONTENT_USER} | grep ^givenName: | perl -p -e 's/givenName: //g')
TITRE=$(cat ${CONTENT_USER} | grep ^title: | perl -p -e 's/title: //g')
# Traitement des initiales
# Si existe dans LDAP, on récupère dans le LDAP
INITIALES=$(cat ${CONTENT_USER} | grep ^initials: | perl -p -e 's/initials: //g')
# Si les initiales ne sont pas renseignée dans le LDAP on les génère depuis le Nom et le Prénom
[[ -z ${INITIALES} ]] && INITIALES="${PRENOM:0:1}${NOM:0:1}"

# Email
# Si plusieurs emails sont renseignés pour l'utilisateur dans le LDAP on garde prioritairement 
# celui qui contient l'UID de l'utilisateur 
# et si le paramètre -d est utilisé on garde prioritairement (si l'un des emails correspond)
# une adresse email qui contient le nom de domaine renseigné en paramètre
cat ${CONTENT_USER} | grep ^mail: | perl -p -e 's/mail: //g' > ${LISTE_MAIL}
LINES_NUMBER=$(cat ${LISTE_MAIL} | grep "." | wc -l) 
if [ ${LINES_NUMBER} -eq 1 ]; then
	MAIL=$(head -n 1 ${LISTE_MAIL})
elif [ ${LINES_NUMBER} -gt 1 ]; then
	if [ -z ${DOMAIN_EMAIL} ]; then
		cat ${LISTE_MAIL} | grep ${USER_UID} > /dev/null 2>&1
		if [ $? -ne 0 ]; then
			MAIL=$(head -n 1 ${LISTE_MAIL})
		else
			MAIL=$(cat ${LISTE_MAIL} | grep ${USER_UID} | head -n 1)
		fi
	else
		cat ${LISTE_MAIL} | grep ${DOMAIN_EMAIL} | grep ${USER_UID} > /dev/null 2>&1
		if [ $? -eq 0 ]; then
			MAIL=$(cat ${LISTE_MAIL} | grep ${DOMAIN_EMAIL} | grep ${USER_UID} | head -n 1)
		else
			cat ${LISTE_MAIL} | grep ${DOMAIN_EMAIL} > /dev/null 2>&1
			if [ $? -eq 0 ]; then
				MAIL=$(cat ${LISTE_MAIL} | grep ${DOMAIN_EMAIL} | head -n 1)
			else
				cat ${LISTE_MAIL} | grep ${USER_UID} > /dev/null 2>&1
				if [ $? -eq 0 ]; then
					MAIL=$(cat ${LISTE_MAIL} | grep ${USER_UID} | head -n 1)
				else
					MAIL=$(head -n 1 ${LISTE_MAIL})
				fi
			fi
		fi
	fi
fi

# Fonction formatant au format international les numéros de téléphone
function telFormat () {
	NUMBER_TEL=$(echo ${1} | perl -p -e 's/\.//g' | perl -p -e 's/ //g' | perl -p -e 's/\(//g' | perl -p -e 's/\)//g')
	if [[ ${#NUMBER_TEL} -eq 10 ]] && [[ ${NUMBER_TEL:0:1} -eq 0 ]]; then
		echo ${NUMBER_TEL:0:2}" "${NUMBER_TEL:2:2}" "${NUMBER_TEL:4:2}" "${NUMBER_TEL:6:2}" "${NUMBER_TEL:8:2}
	elif [[ ${#NUMBER_TEL} -eq 12 ]] && [[ ${NUMBER_TEL:0:1} == "+" ]]; then
		echo ${NUMBER_TEL:0:3}" (0)"${NUMBER_TEL:3:1}" "${NUMBER_TEL:4:2}" "${NUMBER_TEL:6:2}" "${NUMBER_TEL:8:2}" "${NUMBER_TEL:10:2}
	elif [[ ${#NUMBER_TEL} -eq 13 ]] && [[ ${NUMBER_TEL:0:1} == "+" ]]; then
		echo ${NUMBER_TEL:0:3}" (0)"${NUMBER_TEL:4:1}" "${NUMBER_TEL:5:2}" "${NUMBER_TEL:7:2}" "${NUMBER_TEL:9:2}" "${NUMBER_TEL:11:2}
	else
		echo ${NUMBER_TEL}
	fi
}

# Traitement numéro de téléphone direct
OLDIFS=$IFS; IFS=$'\n'
for LINE in $(cat ${CONTENT_USER} | grep ^telephoneNumber: | perl -p -e 's/telephoneNumber: //g'| perl -p -e 's/ //g')
do
	 telFormat ${LINE} >> ${LISTE_TEL}
done
LIGNEDIRECTE=$(cat ${LISTE_TEL} | perl -p -e 's/\n/ - /g' | awk 'sub( "...$", "" )')
IFS=$OLDIFS

# Traitement numéro de téléphone portable pro
OLDIFS=$IFS; IFS=$'\n'
for LINE in $(cat ${CONTENT_USER} | grep ^mobile: | perl -p -e 's/mobile: //g'| perl -p -e 's/ //g')
do
	 telFormat ${LINE} >> ${LISTE_MOBILE}
done
MOBILE=$(cat ${LISTE_MOBILE} | perl -p -e 's/\n/ - /g' | awk 'sub( "...$", "" )')
IFS=$OLDIFS

# Modifier le fichier source (template LibreOffice)
cat ${MODELE} | perl -p -e "s/NOMCOMPLET/${NOMCOMPLET}/g" | perl -p -e "s/LIGNEDIRECTE/${LIGNEDIRECTE}/g" | sed "s/MAIL/${MAIL}/" | perl -p -e "s/TITRE/${TITRE}/g" | perl -p -e "s/INITIALES/${INITIALES}/g"> ${MODELE}.new && mv ${MODELE} ${MODELE}.old && mv ${MODELE}.new ${MODELE} && rm ${MODELE}.old
[[ ! -z ${MOBILE} ]] &&	cat ${MODELE} | perl -p -e "s/MOBILE/${MOBILE}/g" > ${MODELE}.new && mv ${MODELE} ${MODELE}.old && mv ${MODELE}.new ${MODELE} && rm ${MODELE}.old
[[ -z ${MOBILE} ]] && cat ${MODELE} | perl -p -e "s/Mobile :/ /g" | perl -p -e "s/MOBILE/ /g" > ${MODELE}.new && mv ${MODELE} ${MODELE}.old && mv ${MODELE}.new ${MODELE} && rm ${MODELE}.old

# Préparation du Nom du fichier template LibreOffice
[[ ${TAG} == "" ]] && NOUVEAU_NOM=$(echo ${RACINE} | tr [a-z] [A-Z])-$(echo ${INITIALES} | tr [a-z] [A-Z])
[[ ! ${TAG} == "" ]] && NOUVEAU_NOM=$(echo ${TAG})-$(echo ${RACINE} | tr [a-z] [A-Z])-$(echo ${INITIALES} | tr [a-z] [A-Z])
# Modifier méta
cat ${META} | perl -p -e "s/${RACINE}/${NOUVEAU_NOM}/g" > ${META}.new && mv ${META} ${META}.old && mv ${META}.new ${META} && rm ${META}.old

# ZIP fichier source
cd ${DIR_MODELE}
echo -e "\nZIP du nouveau template :"
zip -r newtemplate.ott *
[ $? -ne 0 ] && error 7 "Problème pour créer l'archive '${DIR_MODELE}/newtemplate.ott'."

# Déplacer dans le répertoire souhaité le résultat
echo -e "\nDéplacement vers '${DIR_EXPORT}/${NOUVEAU_NOM}.ott' :"
mv "${DIR_MODELE}/newtemplate.ott" "${DIR_EXPORT}/${NOUVEAU_NOM}.ott"
[ $? -ne 0 ] && error 7 "Problème pour déplacer le fichier à l'emplacement '${DIR_EXPORT}/${NOUVEAU_NOM}.ott'."
cd ~

alldone 0