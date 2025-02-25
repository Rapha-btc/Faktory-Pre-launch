;; 6108072201d8fcadfae56973d572ec5e5c83287bd75bbc6768fcc6181c30d6d6
;; txt6 Powered By Faktory.fun v1.0 

(impl-trait 'STTWD9SPRQVD3P733V89SV0P8RZRZNQADG034F0A.faktory-trait-v1.sip-010-trait)
(impl-trait 'STTWD9SPRQVD3P733V89SV0P8RZRZNQADG034F0A.aibtcdev-dao-traits-v1.token)

(define-constant ERR-NOT-AUTHORIZED u401)
(define-constant ERR-NOT-OWNER u402)

(define-fungible-token TXT6 MAX)
(define-constant MAX u100000000000000)
(define-data-var contract-owner principal 'STRZ4P1ABSVSZPC4HZ4GDAW834HHEHJMF65X5S6D.txt6-token-owner)
(define-data-var token-uri (optional (string-utf8 256)) (some u"wwww.txt6.com"))

;; SIP-10 Functions
(define-public (transfer (amount uint) (sender principal) (recipient principal) (memo (optional (buff 34))))
    (begin
       (asserts! (is-eq tx-sender sender) (err ERR-NOT-AUTHORIZED))
       (match (ft-transfer? TXT6 amount sender recipient)
          response (begin
            (print memo)
            (ok response))
          error (err error)
        )
    )
)

(define-public (set-token-uri (value (string-utf8 256)))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) (err ERR-NOT-AUTHORIZED))
        (var-set token-uri (some value))
        (ok (print {
              notification: "token-metadata-update",
              payload: {
                contract-id: (as-contract tx-sender),
                token-class: "ft"
              }
            })
        )
    )
)

(define-read-only (get-balance (account principal))
  (ok (ft-get-balance TXT6 account))
)

(define-read-only (get-name)
  (ok "TEXT6")
)

(define-read-only (get-symbol)
  (ok "TXT6")
)

(define-read-only (get-decimals)
  (ok u6)
)

(define-read-only (get-total-supply)
  (ok (ft-get-supply TXT6))
)

(define-read-only (get-token-uri)
    (ok (var-get token-uri))
)

(define-public (set-contract-owner (new-owner principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) (err ERR-NOT-AUTHORIZED))
    (print {new-owner: new-owner})
    (ok (var-set contract-owner new-owner))
  )
)

;; ---------------------------------------------------------

(define-public (send-many (recipients (list 200 { to: principal, amount: uint, memo: (optional (buff 34)) })))
  (fold check-err (map send-token recipients) (ok true))
)

(define-private (check-err (result (response bool uint)) (prior (response bool uint)))
  (match prior ok-value result err-value (err err-value))
)

(define-private (send-token (recipient { to: principal, amount: uint, memo: (optional (buff 34)) }))
  (send-token-with-memo (get amount recipient) (get to recipient) (get memo recipient))
)

(define-private (send-token-with-memo (amount uint) (to principal) (memo (optional (buff 34))))
  (let ((transferOk (try! (transfer amount tx-sender to memo))))
    (ok transferOk)
  )
)

;; ---------------------------------------------------------

(define-private (stx-transfer-to (recipient principal) (amount uint))
  (stx-transfer? amount tx-sender recipient)
)

(begin 
    ;; ft distribution
    (try! (ft-mint? TXT6 (/ (* MAX u80) u100) 'STRZ4P1ABSVSZPC4HZ4GDAW834HHEHJMF65X5S6D.txt6-treasury)) ;; 80% treasury
    (try! (ft-mint? TXT6 (/ (* MAX u20) u100) 'STRZ4P1ABSVSZPC4HZ4GDAW834HHEHJMF65X5S6D.txt6-faktory-dex)) ;; 20% dex

    ;; deploy fixed fee
    (try! (stx-transfer-to 'ST2P8Q1Y8M6SB642QMS432SCWP1D01ZE747PCTT26 u500000)) 

    (print { 
        type: "faktory-trait-v1", 
        name: "TEXT6",
        symbol: "TXT6",
        token-uri: u"wwww.txt6.com", 
        tokenContract: (as-contract tx-sender),
        supply: MAX, 
        decimals: u6, 
        targetStx: u2000000000,
        tokenToDex: (/ (* MAX u20) u100),
        tokenToDeployer: u0,
        stxToDex: u0,
        stxBuyFirstFee: u0,
    })
)