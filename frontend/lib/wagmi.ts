import { createConfig, http } from 'wagmi'
import { injected, coinbaseWallet } from 'wagmi/connectors'
import { unichainSepolia } from './eleos/chain'

export const wagmiConfig = createConfig({
  chains: [unichainSepolia],
  transports: {
    [unichainSepolia.id]: http(),
    // Override with a private RPC for production:
    // [unichainSepolia.id]: http(process.env.NEXT_PUBLIC_RPC_URL),
  },
  connectors: [
    injected(),                                          // MetaMask / browser wallet
    coinbaseWallet({ appName: 'Eleos IL Recapture' }),  // Coinbase Wallet
    // walletConnect({ projectId: process.env.NEXT_PUBLIC_WC_PROJECT_ID! }),
  ],
  // Disable SSR since wagmi reads localStorage for persisted state
  ssr: false,
})

// Augment wagmi's module for full TypeScript inference on useReadContract etc.
declare module 'wagmi' {
  interface Register {
    config: typeof wagmiConfig
  }
}
