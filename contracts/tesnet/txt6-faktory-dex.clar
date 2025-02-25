;; 1898d65b168abcd7d774b9cac72f7731ceaa0d1a3b7d60531df91a260f1b447a
    ;; aibtc.dev DAO faktory.fun DEX @version 1.0
  
    (impl-trait 'STTWD9SPRQVD3P733V89SV0P8RZRZNQADG034F0A.aibtcdev-dao-traits-v1-1.faktory-dex)
    (impl-trait 'STTWD9SPRQVD3P733V89SV0P8RZRZNQADG034F0A.faktory-dex-trait-v1-1.dex-trait)
    (use-trait faktory-token 'STTWD9SPRQVD3P733V89SV0P8RZRZNQADG034F0A.faktory-trait-v1.sip-010-trait) 
    
    (define-constant ERR-MARKET-CLOSED (err u1001))
    (define-constant ERR-STX-NON-POSITIVE (err u1002))
    (define-constant ERR-STX-BALANCE-TOO-LOW (err u1003))
    (define-constant ERR-FT-NON-POSITIVE (err u1004))
    (define-constant ERR-FETCHING-BUY-INFO (err u1005)) 
    (define-constant ERR-FETCHING-SELL-INFO (err u1006)) 
    (define-constant ERR-TOKEN-NOT-AUTH (err u401))
    (define-constant ERR-UNAUTHORIZED-CALLER (err u402))
    
    (define-constant FEE-RECEIVER 'ST1Y9QV2CY6R0NQNS8CPA5C2835QNGHMTFE94FV5R)
    (define-constant G-RECEIVER 'ST3BA7GVAKQTCTX68VPAD9W8CBYG71JNMGBCAD48N)
  
    (define-constant DEPLOYER 'STTWD9SPRQVD3P733V89SV0P8RZRZNQADG034F0A)
    (define-constant ORIGINATOR 'STRZ4P1ABSVSZPC4HZ4GDAW834HHEHJMF65X5S6D)
    (define-constant DEX-TOKEN 'STRZ4P1ABSVSZPC4HZ4GDAW834HHEHJMF65X5S6D.txt6-faktory)
    
    ;; token constants
    (define-constant TARGET_STX u2000000000)
    (define-constant FAK_STX u400000000)
    (define-constant GRAD-FEE u40000000)
    
    ;; data vars
    (define-data-var open bool false)
    (define-data-var fak-ustx uint u0)
    (define-data-var ft-balance uint u0)
    (define-data-var stx-balance uint u0)
    (define-data-var premium uint u25)
    
    (define-public (buy (ft <faktory-token>) (ustx uint))
      (begin
        (asserts! (is-eq DEX-TOKEN (contract-of ft)) ERR-TOKEN-NOT-AUTH)
        (asserts! (var-get open) ERR-MARKET-CLOSED)
        (asserts! (> ustx u0) ERR-STX-NON-POSITIVE)
        (let (
              (in-info (unwrap! (get-in ustx) ERR-FETCHING-BUY-INFO))
              (total-stx (get total-stx in-info))
              (total-stk (get total-stk in-info))
              (total-ft (get ft-balance in-info))
              (k (get k in-info))
              (fee (get fee in-info))
              (stx-in (get stx-in in-info))
              (new-stk (get new-stk in-info))
              (new-ft (get new-ft in-info))
              (tokens-out (get tokens-out in-info))
              (new-stx (get new-stx in-info))
              (ft-receiver tx-sender)
              )
          (try! (stx-transfer? fee tx-sender FEE-RECEIVER))
          (try! (stx-transfer? stx-in tx-sender (as-contract tx-sender)))
          (try! (as-contract (contract-call? ft transfer tokens-out tx-sender ft-receiver none)))
          (if (>= new-stx TARGET_STX)
              (let ((premium-amount (/ (* new-ft (var-get premium)) u100))
                    (amm-amount (- new-ft premium-amount))
                    (deployer-amount (/ (* premium-amount u25) u100))
                    (originator-amount (- premium-amount deployer-amount))
                    (amm-ustx (- new-stx GRAD-FEE))
                    (xyk-pool-uri (default-to u"https://bitflow.finance" (try! (contract-call? ft get-token-uri))))
                    (xyk-burn-amount (- (sqrti (* amm-ustx amm-amount)) u1)))
              (try! (as-contract (contract-call? ft transfer deployer-amount tx-sender DEPLOYER none)))
              (try! (as-contract (contract-call? ft transfer originator-amount tx-sender ORIGINATOR none)))
                (try! (as-contract 
                       (contract-call? 
                         'ST295MNE41DC74QYCPRS8N37YYMC06N6Q3VQDZ6G1.xyk-core-v-1-2 
                             create-pool 
                             'STRZ4P1ABSVSZPC4HZ4GDAW834HHEHJMF65X5S6D.xyk-pool-stx-txt6-v-1-1
                             'ST295MNE41DC74QYCPRS8N37YYMC06N6Q3VQDZ6G1.token-stx-v-1-2 
                             ft
                             amm-ustx 
                             amm-amount 
                             xyk-burn-amount 
                             u10 u40 u10 u40 
                             'ST27Q7Z7P5MTJN2B3M9Q406XPCDB1VFZJ3KWX3CES xyk-pool-uri true)))
                (try! (as-contract (stx-transfer? GRAD-FEE tx-sender G-RECEIVER)))
                (var-set open false)
                (var-set stx-balance u0)
                (var-set ft-balance u0)
                (print {type: "buy", ft: (contract-of ft), tokens-out: tokens-out, ustx: ustx, premium-amount: premium-amount, amm-amount: amm-amount,
                        amm-ustx: amm-ustx,
                        stx-balance: u0, ft-balance: u0,
                        fee: fee, grad-fee: GRAD-FEE, maker: tx-sender,
                        open: false})
                (ok true))
              (begin
                  (var-set stx-balance new-stx)
                  (var-set ft-balance new-ft)
                  (print {type: "buy", ft: (contract-of ft), tokens-out: tokens-out, ustx: ustx, maker: tx-sender,
                          stx-balance: new-stx, ft-balance: new-ft,
                          fee: fee,
                          open: true})
              (ok true))))))
    
    (define-read-only (get-in (ustx uint))
      (let ((total-stx (var-get stx-balance))
            (total-stk (+ total-stx (var-get fak-ustx)))
            (total-ft (var-get ft-balance))
            (k (* total-ft total-stk))
            (fee (/ (* ustx u2) u100))
            (stx-in (- ustx fee))
            (new-stk (+ total-stk stx-in))
            (new-ft (/ k new-stk))
            (tokens-out (- total-ft new-ft))
            (raw-to-grad (- TARGET_STX total-stx))
            (stx-to-grad (/ (* raw-to-grad u103) u100)))
        (ok {total-stx: total-stx,
             total-stk: total-stk,
             ft-balance: total-ft,
             k: k,
             fee: fee,
             stx-in: stx-in,
             new-stk: new-stk,
             new-ft: new-ft,
             tokens-out: tokens-out,
             new-stx: (+ total-stx stx-in),
             stx-to-grad: stx-to-grad
             })))
    
    (define-public (sell (ft <faktory-token>) (amount uint))
      (begin
        (asserts! (is-eq DEX-TOKEN (contract-of ft)) ERR-TOKEN-NOT-AUTH)
        (asserts! (var-get open) ERR-MARKET-CLOSED)
        (asserts! (> amount u0) ERR-FT-NON-POSITIVE)
        (let (
              (out-info (unwrap! (get-out amount) ERR-FETCHING-SELL-INFO))
              (total-stx (get total-stx out-info))
              (total-stk (get total-stk out-info))
              (total-ft (get ft-balance out-info))
              (k (get k out-info))
              (new-ft (get new-ft out-info))
              (new-stk (get new-stk out-info))
              (stx-out (get stx-out out-info))
              (fee (get fee out-info))
              (stx-to-receiver (get stx-to-receiver out-info))
              (new-stx (get new-stx out-info))
              (stx-receiver tx-sender)
              )
          (asserts! (>= total-stx stx-out) ERR-STX-BALANCE-TOO-LOW)
          (try! (contract-call? ft transfer amount tx-sender (as-contract tx-sender) none))
          (try! (as-contract (stx-transfer? stx-to-receiver tx-sender stx-receiver)))
          (try! (as-contract (stx-transfer? fee tx-sender FEE-RECEIVER)))
          (var-set stx-balance new-stx)
          (var-set ft-balance new-ft)
          (print {type: "sell", ft: (contract-of ft), amount: amount, stx-to-receiver: stx-to-receiver, maker: tx-sender,
                  stx-balance: new-stx, ft-balance: new-ft,
                  fee: fee,
                  open: true})
          (ok true))))
    
    (define-read-only (get-out (amount uint))
      (let ((total-stx (var-get stx-balance))
            (total-stk (+ total-stx (var-get fak-ustx)))
            (total-ft (var-get ft-balance))
            (k (* total-ft total-stk))
            (new-ft (+ total-ft amount))
            (new-stk (/ k new-ft))
            (stx-out (- (- total-stk new-stk) u1))
            (fee (/ (* stx-out u2) u100))
            (stx-to-receiver (- stx-out fee)))
        (ok {
             total-stx: total-stx,
             total-stk: total-stk,
             ft-balance: total-ft,
             k: k,
             new-ft: new-ft,
             new-stk: new-stk,
             stx-out: stx-out,
             fee: fee,
             stx-to-receiver: stx-to-receiver,
             amount-in: amount,
             new-stx: (- total-stx stx-out)
             })))
    
    (define-read-only (get-open)
      (ok (var-get open)))
    
    ;; boot dex
      (begin
        (var-set fak-ustx FAK_STX)
        (var-set ft-balance u20000000000000)
        (var-set stx-balance u0)
        (var-set open true)
        (try! (stx-transfer? u500000 tx-sender 'ST2P8Q1Y8M6SB642QMS432SCWP1D01ZE747PCTT26))
          (print { 
              type: "faktory-dex-trait-v1-1", 
              dexContract: (as-contract tx-sender),
              ammReceiver: 'ST295MNE41DC74QYCPRS8N37YYMC06N6Q3VQDZ6G1.xyk-core-v-1-2,
              poolName: 'STRZ4P1ABSVSZPC4HZ4GDAW834HHEHJMF65X5S6D.xyk-pool-stx-txt6-v-1-1
         })
        (ok true))