{-# LANGUAGE CPP, RecordWildCards #-}
module Internal.USBSerial (USBSerial(..), findPort, usbSerials) where

#if defined WIN32
import System.Win32.Registry (hKEY_LOCAL_MACHINE, regOpenKey, regCloseKey, regQueryValue, regQueryValueEx)
import System.Win32.Types (DWORD, HKEY)
#endif
import Control.Exception (handle, bracket, SomeException(..))
import Foreign (toBool, Storable(peek, sizeOf), castPtr, alloca) 
import Data.List.Split (splitOn)
import Data.List (stripPrefix)
import Numeric (readHex, showHex)
import Data.Maybe (catMaybes, listToMaybe)
import Control.Monad (forM)

data USBSerial = USBSerial
    { key           :: String
    , vendorId      :: Int
    , productId     :: Int
    , portName      :: String
    , friendlyName  :: String
    }

instance Show USBSerial where
    show USBSerial{..} = unwords [ portName, toHex vendorId, toHex productId, friendlyName ]
        where toHex x = let s = showHex x "" in replicate (4 - length s) '0' ++ s

findPort :: Int -> Int -> IO (Maybe String)
findPort vendorId productId = fmap (fmap portName . listToMaybe) $ usbSerials (Just vendorId) (Just productId)

#if defined WIN32
usbSerials :: Maybe Int -> Maybe Int -> IO [USBSerial]
usbSerials mVendorId mProductId = withHKey hKEY_LOCAL_MACHINE path $ \hkey -> do
    n <- fmap fromEnum $ regQueryValueDWORD hkey "Count"
    fmap catMaybes $ forM [0..n-1] $ \i -> do
        key <- regQueryValue hkey . show $ i
        case keyToVidPid key of
            Just (vendorId, productId)
                | maybe True (==vendorId) mVendorId && maybe True (==productId) mProductId -> do
                    portName <- getPortName key
                    friendlyName <- getFriendlyName key
                    return $ Just USBSerial{..}
            _ -> return Nothing
    where path = "SYSTEM\\CurrentControlSet\\Services\\usbser\\Enum"

getPortName :: String -> IO String
getPortName serial = withHKey hKEY_LOCAL_MACHINE path $ flip regQueryValue "PortName"
    where path = "SYSTEM\\CurrentControlSet\\Enum\\" ++ serial ++ "\\Device Parameters"

getFriendlyName :: String -> IO String
getFriendlyName serial = withHKey hKEY_LOCAL_MACHINE path $ flip regQueryValue "FriendlyName"
    where path = "SYSTEM\\CurrentControlSet\\Enum\\" ++ serial

keyToVidPid :: String -> Maybe (Int, Int)
keyToVidPid name
    | (_:s:_) <- splitOn "\\" name
    , (v:p:_) <- splitOn "&" s
    , Just v <- fromHex =<< stripPrefix "VID_" v
    , Just p <- fromHex =<< stripPrefix "PID_" p = Just (v, p)
    | otherwise = Nothing
    where fromHex s = case readHex s of
            [(x, "")] -> Just x
            _         -> Nothing
withHKey :: HKEY -> String -> (HKEY -> IO a) -> IO a
withHKey hive path
    = handle (\(SomeException e) -> error $ show e ++ ": " ++ path)
    . bracket (regOpenKey hive path) regCloseKey

-- | Read DWORD value from registry.
-- From http://compgroups.net/comp.lang.haskell/working-with-the-registry-windows-xp/2579164
regQueryValueDWORD :: HKEY -> String -> IO DWORD
regQueryValueDWORD hkey name = alloca $ \ptr -> do
    regQueryValueEx hkey name (castPtr ptr) (sizeOf (undefined :: DWORD))
    peek ptr
#else
usbSerials :: Maybe Int -> Maybe Int -> IO [USBSerial]
usbSerials _ _ = pure []
#endif

