;; Pre-launch contract for token distribution
;; Fixed allocation: 20 seats at 7.5 STX each
;; Each seat gets 1M tokens with backloaded vesting

(use-trait faktory-token .faktory-trait-v1.sip-010-trait) ;; 'SP3XXMS38VTAWTVPE5682XSBFXPTH7XCPEBTX8AN2

(define-constant SEATS u20)
(define-constant PRICE-PER-SEAT u7500000) ;; 7.5 STX in microSTX
(define-constant TOKENS-PER-SEAT u2000000) ;; 2M tokens per seat
(define-constant DAO-TOKEN .nothing-faktory) ;; 'SP2XCME6ED8RERGR9R7YDZW7CA6G3F113Y8JMVA46

;; Vesting schedule (percentages add up to 100)
(define-constant VESTING-SCHEDULE 
    (list 
        {height: u100, percent: u10}  ;; 10% at start
        {height: u200, percent: u20}  ;; 20% more
        {height: u300, percent: u30}  ;; 30% more
        {height: u400, percent: u40})) ;; Final 40%

;; Data vars
(define-data-var total-seats-taken uint u0)
(define-data-var token-contract (optional principal) none)
(define-data-var distribution-height (optional uint) none)

;; Track seat owners and claims
(define-map seat-owners uint principal)
(define-map has-seat principal bool)
(define-map claimed-amounts principal uint)

;; Error constants
(define-constant ERR-ALREADY-HAS-SEAT (err u300))
(define-constant ERR-NO-SEATS-LEFT (err u301))
(define-constant ERR-TRANSFER-FAILED (err u302))
(define-constant ERR-NOT-SEAT-OWNER (err u303))
(define-constant ERR-NOT-INITIALIZED (err u304))
(define-constant ERR-ALREADY-CLAIMED (err u305))
(define-constant ERR-NOTHING-TO-CLAIM (err u306))
(define-constant ERR-NOT-AUTHORIZED (err u307))
(define-constant ERR-ALREADY-INITIALIZED (err u308))
(define-constant ERR-WRONG-TOKEN (err u309))


;; Main function to buy a seat
(define-public (buy-seat)
    (let 
        ((current-seats (var-get total-seats-taken)))
        (asserts! (< current-seats SEATS) ERR-NO-SEATS-LEFT)
        (asserts! (is-none (map-get? has-seat tx-sender)) ERR-ALREADY-HAS-SEAT)
        
        ;; Process payment
        (match (stx-transfer? PRICE-PER-SEAT tx-sender (as-contract tx-sender))
            success 
                (begin
                    ;; Record seat ownership
                    (map-set seat-owners current-seats tx-sender)
                    (map-set has-seat tx-sender true)
                    (var-set total-seats-taken (+ current-seats u1))
                    (ok true))
            error ERR-TRANSFER-FAILED)))

;; Initialize token contract reference and start vesting
(define-public (initialize-token-distribution)
    (begin
        (asserts! (is-eq tx-sender DAO-TOKEN) ERR-NOT-AUTHORIZED)
        (asserts! (is-none (var-get token-contract)) ERR-ALREADY-INITIALIZED)
        (var-set token-contract (some DAO-TOKEN))
        (var-set distribution-height (some burn-block-height))
        (ok true)))

;; Calculate claimable amount based on vesting schedule
;; Calculate claimable amount based on vesting schedule
(define-private (get-claimable-amount (owner principal))
    (match (var-get distribution-height) 
        start-height 
            (let ((claimed (default-to u0 (map-get? claimed-amounts owner)))
                  (vested (fold check-claimable VESTING-SCHEDULE u0)))
                (- vested claimed))
        ;; If distribution not initialized, nothing is claimable
        u0))

(define-private (check-claimable (entry {height: uint, percent: uint}) (current-total uint))
    (if (<= (+ (unwrap-panic (var-get distribution-height)) (get height entry)) burn-block-height)
        (+ current-total (/ (* TOKENS-PER-SEAT (get percent entry)) u100))
        current-total))

;; Claim vested tokens
(define-public (claim (ft <faktory-token>))
    (let ((claimable (get-claimable-amount tx-sender)))
        (asserts! (is-eq (var-get token-contract) (some DAO-TOKEN)) ERR-NOT-INITIALIZED) 
        (asserts! (is-eq (contract-of ft) DAO-TOKEN) ERR-WRONG-TOKEN)
        (asserts! (default-to false (map-get? has-seat tx-sender)) ERR-NOT-SEAT-OWNER)
        (asserts! (> claimable u0) ERR-NOTHING-TO-CLAIM)
        (match (contract-call? ft transfer claimable (as-contract tx-sender) tx-sender none)
            success
                (begin
                    (map-set claimed-amounts tx-sender 
                        (+ (default-to u0 (map-get? claimed-amounts tx-sender)) claimable))
                    (ok claimable))
            error (err ERR-TRANSFER-FAILED))))

;; Read only functions
(define-read-only (get-remaining-seats)
    (- SEATS (var-get total-seats-taken)))

(define-read-only (has-seat? (address principal))
    (default-to false (map-get? has-seat address)))

(define-read-only (get-seat-owner (seat-number uint))
    (map-get? seat-owners seat-number))

(define-read-only (get-claimed-amount (address principal))
    (default-to u0 (map-get? claimed-amounts address)))

(define-read-only (get-vesting-schedule)
    VESTING-SCHEDULE)