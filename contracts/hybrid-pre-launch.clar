;; Pre-launch contract for token distribution
;; Dynamic allocation: 1-7 seats per user in Period 1
;; Each seat = 7.5 STX, targeting 20 seats total with minimum 10 users
;; Question: will there be lots of failed tsx as a result of buyers buying more than max seat per user

(use-trait faktory-token .faktory-trait-v1.sip-010-trait)

(define-constant SEATS u20)
(define-constant MIN-USERS u10)
(define-constant MAX-SEATS-PER-USER u7)
(define-constant PRICE-PER-SEAT u7500000) ;; 7.5 STX in microSTX
(define-constant TOKENS-PER-SEAT u2000000000000) ;; 2M tokens per seat
(define-constant EXPIRATION-PERIOD u2100) ;; 1 Stacks reward cycle in PoX-4
(define-constant PERIOD-2-LENGTH u100) ;; blocks for redistribution period
(define-constant DAO-TOKEN .nothing-faktory)

;; Vesting schedule (percentages add up to 100)
(define-constant VESTING-SCHEDULE
    (list 
        {height: u100, percent: u10}  ;; 10% at start
        {height: u1000, percent: u20}  ;; 20% more
        {height: u2100, percent: u30}  ;; 30% more
        {height: u4200, percent: u40})) ;; Final 40%

;; Data vars
(define-data-var ft-balance uint u0)
(define-data-var stx-balance uint u0)
(define-data-var total-seats-taken uint u0)
(define-data-var total-users uint u0)
(define-data-var token-contract (optional principal) none)
(define-data-var distribution-height (optional uint) none)
(define-data-var deployment-height (optional uint) none)
(define-data-var period-2-height (optional uint) none)
(define-data-var target-owner principal 'SP000000000000000000002Q6VF78)

;; Define a data variable to track seat holders
(define-data-var seat-holders (list 20 {owner: principal, seats: uint}) (list))

;; Track seat ownership and claims
(define-map seats-owned principal uint)
(define-map claimed-amounts principal uint)

;; Error constants
(define-constant ERR-TOO-MANY-SEATS (err u300))
(define-constant ERR-NO-SEATS-LEFT (err u301))
(define-constant ERR-NOT-SEAT-OWNER (err u302))
(define-constant ERR-NOT-INITIALIZED (err u303))
(define-constant ERR-NOTHING-TO-CLAIM (err u304))
(define-constant ERR-NOT-AUTHORIZED (err u305))
(define-constant ERR-ALREADY-INITIALIZED (err u306))
(define-constant ERR-WRONG-TOKEN (err u307))
(define-constant ERR-ALREADY-EXPIRED (err u308))
(define-constant ERR-NOT-EXPIRED (err u309))
(define-constant ERR-NO-REFUND (err u310))
(define-constant ERR-CONTRACT-INSUFFICIENT-FUNDS (err u311))
(define-constant ERR-PERIOD-2-MULTIPLE-SEATS (err u312))
(define-constant ERR-INVALID-SEAT-COUNT (err u313))
(define-constant ERR-SLICE-FAILED (err u314))
(define-constant ERR-TOO-LONG (err u315))
(define-constant ERR-REMOVING-HOLDER (err u316))

;; Helper functions for period management
(define-private (is-period-1-expired)
    (match (var-get deployment-height)
        start-height (>= burn-block-height (+ start-height EXPIRATION-PERIOD))
        false))

(define-private (is-in-period-2)
    (match (var-get period-2-height)
        start-height (< burn-block-height (+ start-height PERIOD-2-LENGTH))
        false))

(define-private (get-max-seats-allowed)
    (let (
        (seats-remaining (- SEATS (var-get total-seats-taken)))    ;; 13 seats left
        (users-remaining (- MIN-USERS (var-get total-users)))      ;; 9 users needed
        (max-possible (+ (- seats-remaining users-remaining) u1))) ;; (13 - 9) + 1 = 5 seats possible
        (if (>= max-possible MAX-SEATS-PER-USER)
            MAX-SEATS-PER-USER
            max-possible)))

;; Helper function to update seat holders list
(define-private (update-seat-holder (owner principal) (seat-count uint))
  (let ((current-holders (var-get seat-holders))
        (updated-list (update-or-add-holder current-holders owner seat-count)))
    (var-set seat-holders updated-list)))

;; Helper to update or add a holder to the list
(define-private (update-or-add-holder 
    (holders (list 20 {owner: principal, seats: uint}))
    (owner principal)
    (seat-count uint))
  (let ((position (find-holder-position holders owner)))
    (if (is-some position)
        ;; Update existing holder - unwrap the optional result
        (unwrap-panic (replace-at? holders (unwrap-panic position) {owner: owner, seats: seat-count}))
        ;; Add new holder
        (unwrap-panic (as-max-len? (append holders {owner: owner, seats: seat-count}) u20)))))

;; Helper to find a holder's position in the list
(define-private (find-holder-position 
    (holders (list 20 {owner: principal, seats: uint}))
    (owner principal))
  (let ((result (fold check-if-owner 
                     holders 
                     {found: false, index: u0, current: u0})))
    (var-set target-owner owner)
    (if (get found result)
        (some (get index result))
        none)))

(define-private (check-if-owner 
    (entry {owner: principal, seats: uint}) 
    (state {found: bool, index: uint, current: uint}))
  (if (get found state)
      ;; Already found, just pass through
      state
      ;; Check if this is the owner we're looking for
      (if (is-eq (get owner entry) (var-get target-owner))
          ;; Found it, update state
          {found: true, index: (get current state), current: (+ (get current state) u1)}
          ;; Not found, increment counter
          {found: false, index: (get index state), current: (+ (get current state) u1)})))

(define-private (remove-seat-holder (holder principal))
  (let ((position (find-holder-position (var-get seat-holders) holder))
        (current-list (var-get seat-holders)))
    (match position 
        pos (let ((before-slice (unwrap! (slice? current-list u0 pos) ERR-SLICE-FAILED))
                  (after-slice (unwrap! (slice? current-list (+ pos u1) (len current-list)) ERR-SLICE-FAILED))
                  (updated-list (unwrap! (as-max-len? (concat before-slice after-slice) u20) ERR-TOO-LONG)))
              (var-set seat-holders updated-list)
              (ok true))
        (ok false))))  ;; If position not found, do nothing

;; Main functions
;; Buy seats in Period 1
(define-public (buy-seats (seat-count uint))
    (let (
        (current-seats (var-get total-seats-taken))
        (user-seats (default-to u0 (map-get? seats-owned tx-sender)))
        (max-allowed (get-max-seats-allowed)))
        
        (asserts! (> seat-count u0) ERR-INVALID-SEAT-COUNT)
        (asserts! (<= seat-count max-allowed) ERR-TOO-MANY-SEATS)
        (asserts! (< current-seats SEATS) ERR-NO-SEATS-LEFT)
        (asserts! (is-none (var-get period-2-height)) ERR-ALREADY-EXPIRED)
        
        ;; Process payment
        (match (stx-transfer? (* PRICE-PER-SEAT seat-count) tx-sender (as-contract tx-sender))
            success 
                (begin
                    ;; Update records
                    (if (is-eq user-seats u0)
                        (var-set total-users (+ (var-get total-users) u1))
                        true) ;; already a user no need to increment
                    (map-set seats-owned tx-sender (+ user-seats seat-count))
                    (var-set total-seats-taken (+ current-seats seat-count))
                    (var-set stx-balance (+ (var-get stx-balance) (* PRICE-PER-SEAT seat-count)))
                    
                    ;; Update our seat holders list
                    (update-seat-holder tx-sender (+ user-seats seat-count))

                    ;; Check if we should start Period 2
                    (if (and (>= (var-get total-users) MIN-USERS) 
                            (>= (var-get total-seats-taken) SEATS))
                        (var-set period-2-height (some burn-block-height))
                        true)
                    (ok true))
            error (err error))))

;; Get highest seat holder for Period 2 reductions
(define-private (get-highest-seat-holder)
    (let ((holders (var-get seat-holders)))
      (if (> (len holders) u0)
          (let ((first-holder (unwrap-panic (element-at holders u0))))
            (some (get owner (fold check-highest holders first-holder))))
          none)))

(define-private (check-highest 
    (entry {owner: principal, seats: uint}) 
    (current-max {owner: principal, seats: uint}))
  (if (>= (get seats entry) (get seats current-max))
      entry
      current-max))

;; Buy exactly one seat in Period 2
(define-public (buy-single-seat)
    (let (
        (current-seats (var-get total-seats-taken))
        (highest-holder (get-highest-seat-holder))
        (holder (unwrap! highest-holder ERR-NOT-INITIALIZED))
        (old-seats (unwrap! (map-get? seats-owned holder) ERR-NOT-INITIALIZED)))
        
        (asserts! (is-some (var-get period-2-height)) ERR-NOT-INITIALIZED)
        (asserts! (is-in-period-2) ERR-ALREADY-EXPIRED)
        (asserts! (< (var-get total-users) SEATS) ERR-NO-SEATS-LEFT)
        
        ;; Process payment and refund highest holder
        (match (stx-transfer? PRICE-PER-SEAT tx-sender holder)
            success 
                (begin
                    ;; Update new buyer
                    (map-set seats-owned tx-sender u1)
                    (var-set total-users (+ (var-get total-users) u1))
                    ;; Reduce highest holder's seats and refund them
                    (map-set seats-owned holder (- old-seats u1))
                    (ok true))
            error (err error))))

;; Initialize token distribution
(define-public (initialize-token-distribution)
    (begin
        (asserts! (is-eq tx-sender DAO-TOKEN) ERR-NOT-AUTHORIZED)
        (asserts! (is-none (var-get token-contract)) ERR-ALREADY-INITIALIZED)
        (asserts! (>= (var-get total-users) MIN-USERS) ERR-NOT-INITIALIZED)
        (var-set token-contract (some DAO-TOKEN))
        (var-set distribution-height (some burn-block-height))
        (var-set ft-balance u20000000000000) ;; 20M tokens
        (ok true)))

;; Refund logic only for Period 1 failures
(define-public (refund)
    (let (
        (user-seats (default-to u0 (map-get? seats-owned tx-sender)))
        (seat-owner tx-sender))
        (asserts! (is-period-1-expired) ERR-NOT-EXPIRED)
        (asserts! (is-none (var-get token-contract)) ERR-ALREADY-INITIALIZED)
        (asserts! (< (var-get total-users) MIN-USERS) ERR-NO-REFUND)
        (asserts! (> user-seats u0) ERR-NOT-SEAT-OWNER)
        
        ;; Process refund
        (match (as-contract (stx-transfer? (* PRICE-PER-SEAT user-seats) tx-sender seat-owner))
            success 
                (let ((is-removed (unwrap! (remove-seat-holder tx-sender) ERR-REMOVING-HOLDER)))
                    (map-delete seats-owned tx-sender)
                    (var-set total-seats-taken (- (var-get total-seats-taken) user-seats))
                    (var-set total-users (- (var-get total-users) u1))
                    (var-set stx-balance (- (var-get stx-balance) (* PRICE-PER-SEAT user-seats)))
                    (ok true))
            error (err error))))

;; Rest of the functions (claiming, vesting, etc.) remain similar to original
;; Just update seat ownership checks to use seats-owned map instead of has-seat
;; Calculate claimable amount based on vesting schedule
(define-private (get-claimable-amount (owner principal))
    (match (var-get distribution-height) 
        start-height 
            (let ((claimed (default-to u0 (map-get? claimed-amounts owner)))
                  (seats-owner (default-to u0 (map-get? seats-owned owner)))
                  (vested (fold check-claimable VESTING-SCHEDULE u0)))
                (- (* vested seats-owner) claimed)) ;; double claiming is impossible    
        u0)) ;; If distribution not initialized, nothing is claimable

(define-private (check-claimable (entry {height: uint, percent: uint}) (current-total uint))
    (if (<= (+ (unwrap-panic (var-get distribution-height)) (get height entry)) burn-block-height)
        (+ current-total (/ (* TOKENS-PER-SEAT (get percent entry)) u100))
        current-total))

;; Claim vested tokens
(define-public (claim (ft <faktory-token>))
    (let ((claimable (get-claimable-amount tx-sender))
          (seat-owner tx-sender))
        (asserts! (is-eq (var-get token-contract) (some DAO-TOKEN)) ERR-NOT-INITIALIZED) 
        (asserts! (is-eq (contract-of ft) DAO-TOKEN) ERR-WRONG-TOKEN)
        (asserts! (> (default-to u0 (map-get? seats-owned tx-sender)) u0) ERR-NOT-SEAT-OWNER)
        (asserts! (> claimable u0) ERR-NOTHING-TO-CLAIM)
        (asserts! (>= (var-get ft-balance) claimable) ERR-CONTRACT-INSUFFICIENT-FUNDS)
        (match (as-contract (contract-call? ft transfer claimable tx-sender seat-owner none))
            success
                (begin
                    (map-set claimed-amounts tx-sender 
                        (+ (default-to u0 (map-get? claimed-amounts tx-sender)) claimable))
                    (var-set ft-balance (- (var-get ft-balance) claimable)) ;; reduce ft-balance by claimable
                    (ok claimable))
            error (err error))))

;; Read only functions
(define-read-only (get-remaining-seats)
    (- SEATS (var-get total-seats-taken)))

(define-read-only (get-seats-owned (address principal))
    (> (default-to u0 (map-get? seats-owned address)) u0))

(define-read-only (get-claimed-amount (address principal))
    (default-to u0 (map-get? claimed-amounts address)))

(define-read-only (get-vesting-schedule)
    VESTING-SCHEDULE)

(define-read-only (get-seat-holders)
    (var-get seat-holders))

;; boot contract
(var-set deployment-height (some burn-block-height))