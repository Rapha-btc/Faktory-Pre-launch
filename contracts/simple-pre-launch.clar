;; Pre-launch contract for token distribution
;; Fixed allocation: 20 seats at 7.5 STX each
;; Each seat gets 1M tokens with backloaded vesting

(define-constant SEATS u20)
(define-constant PRICE-PER-SEAT u75000000) ;; 7.5 STX in microSTX
(define-constant TOKENS-PER-SEAT u1000000) ;; 1M tokens per seat

;; Data vars
(define-data-var total-seats-taken uint u0)

;; Track seat owners
(define-map seat-owners uint principal)
(define-map has-seat principal bool)

;; Error constants
(define-constant ERR-ALREADY-HAS-SEAT (err u300))
(define-constant ERR-NO-SEATS-LEFT (err u301))
(define-constant ERR-TRANSFER-FAILED (err u302))

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

;; Read only functions
(define-read-only (get-remaining-seats)
    (- SEATS (var-get total-seats-taken)))

(define-read-only (has-seat? (address principal))
    (default-to false (map-get? has-seat address)))

(define-read-only (get-seat-owner (seat-number uint))
    (map-get? seat-owners seat-number))
