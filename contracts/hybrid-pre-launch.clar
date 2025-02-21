;; Hybrid Pre-launch with Fixed Seats but Dynamic Allocation
;; Core concept: Users buy "seats" but can buy multiple seats up to a limit

(define-constant MIN-PARTICIPANTS u10)
(define-constant MAX-PARTICIPANTS u20)
(define-constant MIN-SEATS-PER-WALLET u1)  ;; minimum 1 seat
(define-constant MAX-SEATS-PER-WALLET u4)  ;; maximum 4 seats (20% of total if MAX_PARTICIPANTS=20)
(define-constant PRICE-PER-SEAT u7500000)  ;; 7.5 STX per seat
(define-constant TOKENS-PER-SEAT u2000000) ;; 2M tokens per seat

;; Data vars
(define-data-var total-participants uint u0)
(define-data-var total-seats-taken uint u0)

;; Maps
(define-map has-seats principal uint)  ;; tracks how many seats each participant has
(define-map claimed-amounts principal uint)

;; Buy multiple seats
(define-public (buy-seats (seat-count uint))
    (let ((current-seats (var-get total-seats-taken))
          (current-participants (var-get total-participants))
          (wallet-seats (default-to u0 (map-get? has-seats tx-sender))))
        
        ;; Checks
        (asserts! (>= seat-count MIN-SEATS-PER-WALLET) ERR-BELOW-MIN)
        (asserts! (<= seat-count MAX-SEATS-PER-WALLET) ERR-ABOVE-MAX)
        (asserts! (<= (+ current-seats seat-count) (* MAX-PARTICIPANTS MAX-SEATS_PER_WALLET)) ERR-NO-SEATS-LEFT)
        
        ;; New participant check
        (if (is-eq wallet-seats u0)
            (asserts! (< current-participants MAX-PARTICIPANTS) ERR-MAX-PARTICIPANTS)
            true)
        
        ;; Payment and recording
        (match (stx-transfer? (* PRICE-PER-SEAT seat-count) tx-sender (as-contract tx-sender))
            success 
                (begin
                    (if (is-eq wallet-seats u0)
                        (var-set total-participants (+ current-participants u1))
                        true)
                    (map-set has-seats tx-sender (+ wallet-seats seat-count))
                    (var-set total-seats-taken (+ current-seats seat-count))
                    (ok true))
            error (err error))))