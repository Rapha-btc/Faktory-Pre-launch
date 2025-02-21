;; Dynamic Pre-launch contract with parallel vesting
;; Minimum 20 participants
;; Maximum contribution relative to total target (150 STX)

(use-trait faktory-token .faktory-trait-v1.sip-010-trait)

;; Constants
(define-constant MIN-PARTICIPANTS u20)
(define-constant TARGET-STX u150000000) ;; 150 STX in microSTX
(define-constant MAX-SHARE u75000000) ;; 75 STX max per participant (50% of total)
(define-constant MIN-CONTRIBUTION u1000000) ;; 1 STX minimum
(define-constant TOTAL-ALLOCATION u40000000) ;; 40M tokens for pre-launch
(define-constant DAO-TOKEN .nothing-faktory)

;; Vesting schedule stays backloaded (percentages add up to 100)
(define-constant VESTING-SCHEDULE 
    (list 
        {height: u100, percent: u10}  ;; 10% at start
        {height: u200, percent: u20}  ;; 20% more
        {height: u300, percent: u30}  ;; 30% more
        {height: u400, percent: u40})) ;; Final 40%

;; Data vars
(define-data-var total-participants uint u0)
(define-data-var total-contribution uint u0)
(define-data-var token-contract (optional principal) none)
(define-data-var distribution-height (optional uint) none)

;; Maps
(define-map participant-contributions principal uint)
(define-map participant-allocation principal uint) ;; why do we need this?
(define-map claimed-amounts principal uint)

;; Error constants
(define-constant ERR-BELOW-MIN (err u300))
(define-constant ERR-ABOVE-MAX (err u301))
(define-constant ERR-NOT-INITIALIZED (err u303))
(define-constant ERR-ALREADY-INITIALIZED (err u304))
(define-constant ERR-NOT-AUTHORIZED (err u305))
(define-constant ERR-NOTHING-TO-CLAIM (err u306))
(define-constant ERR-WRONG-TOKEN (err u307))
(define-constant ERR-TARGET-REACHED (err u308))

;; Contribute to pre-launch
(define-public (contribute (amount uint))
    (let 
        ((current-total (var-get total-contribution)))
        
        ;; Check contribution limits
        (asserts! (>= amount MIN-CONTRIBUTION) ERR-BELOW-MIN)
        (asserts! (<= amount MAX-SHARE) ERR-ABOVE-MAX)
        (asserts! (<= (+ current-total amount) TARGET-STX) ERR-TARGET-REACHED)
        
        ;; Process payment
        (match (stx-transfer? amount tx-sender (as-contract tx-sender))
            success 
                (begin
                    ;; Update participant data
                    (if (is-none (map-get? participant-contributions tx-sender))
                        (var-set total-participants (+ (var-get total-participants) u1))
                        true)
                    
                    (map-set participant-contributions 
                        tx-sender 
                        (+ (default-to u0 (map-get? participant-contributions tx-sender)) amount))
                    
                    (var-set total-contribution (+ current-total amount))
                    (ok true))
            error (err error))))

;; Initialize distribution
(define-public (initialize-distribution)
    (begin
        (asserts! (is-eq tx-sender DAO-TOKEN) ERR-NOT-AUTHORIZED)
        (asserts! (>= (var-get total-participants) MIN-PARTICIPANTS) ERR-BELOW-MIN)
        (asserts! (is-none (var-get token-contract)) ERR-ALREADY-INITIALIZED)
        
        ;; Calculate token allocations proportional to contribution
        (map-set participant-allocation
            tx-sender
            (/ (* (unwrap-panic (map-get? participant-contributions tx-sender)) TOTAL-ALLOCATION)
               (var-get total-contribution)))
               
        (var-set token-contract (some DAO-TOKEN))
        (var-set distribution-height (some burn-block-height))
        (ok true)))

;; Calculate claimable amount based on vesting schedule
(define-private (get-claimable-amount (owner principal))
    (match (var-get distribution-height) 
        start-height 
            (let ((claimed (default-to u0 (map-get? claimed-amounts owner)))
                  (allocation (unwrap! (map-get? participant-allocation owner) u0))
                  (vested (fold check-claimable VESTING-SCHEDULE u0)))
                (- vested claimed))
        u0))

(define-private (check-claimable (entry {height: uint, percent: uint}) (current-total uint))
    (let ((user-allocation (unwrap! (map-get? participant-allocation tx-sender) u0)))
        (if (<= (+ (unwrap-panic (var-get distribution-height)) (get height entry)) burn-block-height)
            (+ current-total 
                (/ (* user-allocation (get percent entry)) u100))
            current-total)))

;; Claim vested tokens
(define-public (claim (ft <faktory-token>))
    (let ((claimable (get-claimable-amount tx-sender)))
        (asserts! (is-eq (var-get token-contract) (some DAO-TOKEN)) ERR-NOT-INITIALIZED)
        (asserts! (is-eq (contract-of ft) DAO-TOKEN) ERR-WRONG-TOKEN)
        (asserts! (> claimable u0) ERR-NOTHING-TO-CLAIM)
        
        (match (contract-call? ft transfer claimable (as-contract tx-sender) tx-sender none)
            success
                (begin
                    (map-set claimed-amounts tx-sender 
                        (+ (default-to u0 (map-get? claimed-amounts tx-sender)) claimable))
                    (ok claimable))
            error (err error))))

;; Read only functions
(define-read-only (get-contribution (participant principal))
    (default-to u0 (map-get? participant-contributions participant)))

(define-read-only (get-total-contribution)
    (var-get total-contribution))

(define-read-only (get-participant-count)
    (var-get total-participants))

(define-read-only (get-allocation (participant principal))
    (default-to u0 (map-get? participant-allocation participant)))

(define-read-only (get-claimed (participant principal))
    (default-to u0 (map-get? claimed-amounts participant)))