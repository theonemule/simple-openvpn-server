#!/bin/bash

#The admin interface for OpenVPN

echo "Content-type: text/html"
echo ""
echo "<!doctype html>
<html lang=\"en\">
  <head>
    <meta charset=\"utf-8\">
    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1, shrink-to-fit=no\">
    <meta name=\"description\" content=\" A simple OpenVPN server with a web-based admin panel..\">
    <meta name=\"author\" content=\"Blaize Stewart\">
    <title>Simple OpenVPN Server</title>


    <!-- Bootstrap core CSS -->
  <link rel=\"stylesheet\" href=\"https://stackpath.bootstrapcdn.com/bootstrap/4.4.1/css/bootstrap.min.css\" >


<meta name=\"theme-color\" content=\"#563d7c\">


    <style>
	
	  body {
		padding-top:100px;
	  }	

      .bd-placeholder-img {
        font-size: 1.125rem;
        text-anchor: middle;
        -webkit-user-select: none;
        -moz-user-select: none;
        -ms-user-select: none;
        user-select: none;
      }

      @media (min-width: 768px) {
        .bd-placeholder-img-lg {
          font-size: 3.5rem;
        }
      }
	  
  
    </style>
    <!-- Custom styles for this template -->

  </head>

  
<body >


<nav class=\"navbar navbar-expand-md navbar-dark bg-dark fixed-top\">
<a class=\"navbar-brand\" href=\"#\">Simple OpenVPN Server</a>
<button class=\"navbar-toggler\" type=\"button\" data-toggle=\"collapse\" data-target=\"#navbarsExampleDefault\" aria-controls=\"navbarsExampleDefault\" aria-expanded=\"false\" aria-label=\"Toggle navigation\">
<span class=\"navbar-toggler-icon\"></span>
</button>

<div class=\"collapse navbar-collapse\" id=\"navbarsExampleDefault\">
<ul class=\"navbar-nav mr-auto\">
</ul>
</div>
</nav>

<main role=\"main\" class=\"container\">

<div class=\"container\">"


eval `echo "${QUERY_STRING}"|tr '&' ';'`

IP=$(wget -4qO- "http://whatismyip.akamai.com/")

newclient () {
	# Generates the custom client.ovpn
	cp /etc/openvpn/client-common.txt /etc/openvpn/clients/$1.ovpn
	echo "<ca>" >> /etc/openvpn/clients/$1.ovpn
	cat /etc/openvpn/easy-rsa/pki/ca.crt >> /etc/openvpn/clients/$1.ovpn
	echo "</ca>" >> /etc/openvpn/clients/$1.ovpn
	echo "<cert>" >> /etc/openvpn/clients/$1.ovpn
	cat /etc/openvpn/easy-rsa/pki/issued/$1.crt >> /etc/openvpn/clients/$1.ovpn
	echo "</cert>" >> /etc/openvpn/clients/$1.ovpn
	echo "<key>" >> /etc/openvpn/clients/$1.ovpn
	cat /etc/openvpn/easy-rsa/pki/private/$1.key >> /etc/openvpn/clients/$1.ovpn
	echo "</key>" >> /etc/openvpn/clients/$1.ovpn
	echo "<tls-auth>" >> /etc/openvpn/clients/$1.ovpn
	cat /etc/openvpn/ta.key >> /etc/openvpn/clients/$1.ovpn
	echo "</tls-auth>" >> /etc/openvpn/clients/$1.ovpn
}

cd /etc/openvpn/easy-rsa/

case $option in
	"add") #Add a client
		./easyrsa build-client-full $client nopass
		# Generates the custom client.ovpn
		newclient "$client"
		echo "<h3>Certificate for client <span style='color:red'>$client</span> added.</h3>"
	;;
	"revoke") #Revoke a client
		echo "<span style='display:none'>"
		./easyrsa --batch revoke $client
		./easyrsa gen-crl
		echo "</span>"
		rm -rf pki/reqs/$client.req
		rm -rf pki/private/$client.key
		rm -rf pki/issued/$client.crt
		rm -rf /etc/openvpn/crl.pem
		cp /etc/openvpn/easy-rsa/pki/crl.pem /etc/openvpn/crl.pem
		# CRL is read with each client connection, when OpenVPN is dropped to nobody
		echo "<h3>Certificate for client <span style='color:red'>$client</span> revoked.</h3>"
	;;
esac

NUMBEROFCLIENTS=$(tail -n +2 /etc/openvpn/easy-rsa/pki/index.txt | grep -c "^V")
if [[ "$NUMBEROFCLIENTS" = '0' ]]; then
	echo "<h3>You have no existing clients.<h3>"
else

	echo "<div class=\"container\">"

	while read c; do
		if [[ $(echo $c | grep -c "^V") = '1' ]]; then
			clientName=$(echo $c | cut -d '=' -f 2)
			
			if [[ "$clientName" != "server" ]] ; then			
				echo "<div class=\"row\"><div class=\"col-md-4\">$clientName</div>"
				echo "<div class=\"col-md-2\"><a href='index.sh?option=revoke&client=$clientName'>🗑️ Revoke</a></div>"
				echo "<div class=\"col-md-2\"><a target='_blank' href='download.sh?client=$clientName'>📥 Download</a></div></div>"
			fi
		fi
	done </etc/openvpn/easy-rsa/pki/index.txt
	
	echo "</div>"
	
fi

echo "
<div class=\"container\">
<form action='index.sh' method='get'>
<input type='hidden' name='option' value='add'>
New Client: <input type='text' name='client'><input type='submit' value='Add'>
</form>
</div>
"


echo "</div>

</main>



<script src=\"https://code.jquery.com/jquery-3.4.1.slim.min.js\" integrity=\"sha384-J6qa4849blE2+poT4WnyKhv5vZF5SrPo0iEjwBvKU7imGFAV0wwj1yYfoRSJoZ+n\" crossorigin=\"anonymous\"></script>
<script src=\"https://cdn.jsdelivr.net/npm/popper.js@1.16.0/dist/umd/popper.min.js\" integrity=\"sha384-Q6E9RHvbIyZFJoft+2mJbHaEWldlvI9IOYy5n3zV9zzTtmI3UksdQRVvoxMfooAo\" crossorigin=\"anonymous\"></script>
<script src=\"https://stackpath.bootstrapcdn.com/bootstrap/4.4.1/js/bootstrap.min.js\" integrity=\"sha384-wfSDF2E50Y2D1uUdj0O3uMBJnjuUD4Ih7YwaYd1iqfktj0Uod8GCExl3Og8ifwB6\" crossorigin=\"anonymous\"></script>
	  
	  </body>
	  
</html>"
exit 0