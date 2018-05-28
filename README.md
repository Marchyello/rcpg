# Restore Commerce Payment Gateway (RCPG) Microservice  
  
Darbināšanai nepieciešamas Ruby un Bundle instalācijas.  
  
Atkarību atrisināšanai izpildīt:  
`bundle install`  
  
Palaišanai izpildīt:  
`bundle exec ruby run_rcpg.rb`  

config.yml datnē pievienoti PayPal Express Checkout un Authorize.Net starpnieku testa kontu konfigurācijas dati, lai vārteju būtu iespējams darbināt bez papildus konfigurācijas.  

Vārtejas darbināšanai tas nav nepieciešams, taču testa kontiem iespējams pieslēgties arī no starpnieku sistēmām.  
 
[PayPal Express Checkout](https://www.sandbox.paypal.com/) testa konta autentifikācijas dati:  
- lietotājvārds: `rc-bvc-mc@n-fuse.co`  
- parole: `wrcnsSRX3Z4+xxXv`  

[Authorize.Net](https://sandbox.authorize.net/) testa konta autentifikācijas dati:  
- lietotājvārds `68WfcksMe2p6CLt7SRBq`  
- parole: `xYE6^hDqW+^V%-Th`  