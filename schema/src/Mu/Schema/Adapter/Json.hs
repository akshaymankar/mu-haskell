{-# language PolyKinds, DataKinds, GADTs,
             TypeOperators, ScopedTypeVariables,
             MultiParamTypeClasses,
             FlexibleInstances, FlexibleContexts,
             TypeApplications,
             UndecidableInstances #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}
module Mu.Schema.Adapter.Json where

import Data.Aeson
import Data.Aeson.Types
import Data.Functor.Contravariant
import qualified Data.HashMap.Strict as HM
import Data.SOP (NS(..), NP(..))
import qualified Data.Text as T

import Mu.Schema

instance forall sch sty a.
         (HasSchema sch sty a, ToJSON (Term sch (sch :/: sty)))
         => ToJSON (WithSchema sch sty a) where
  toJSON (WithSchema x) = toJSON (toSchema' @sch x)
instance forall sch sty a.
         (HasSchema sch sty a, FromJSON (Term sch (sch :/: sty)))
         => FromJSON (WithSchema sch sty a) where
  parseJSON v = WithSchema . fromSchema' @sch <$> parseJSON v

instance ToJSONFields sch args => ToJSON (Term sch ('DRecord name args)) where
  toJSON (TRecord fields) = Object (toJSONFields fields)
instance FromJSONFields sch args => FromJSON (Term sch ('DRecord name args)) where
  parseJSON (Object v) = TRecord <$> parseJSONFields v
  parseJSON _ = fail "expected object"

class ToJSONFields sch fields where
  toJSONFields :: NP (Field sch) fields -> Object
instance ToJSONFields sch '[] where
  toJSONFields _ = HM.empty
instance forall sch name t fs.
         (KnownName name, ToJSON (FieldValue sch t), ToJSONFields sch fs)
         => ToJSONFields sch ('FieldDef name t ': fs) where
  toJSONFields (Field v :* rest) = HM.insert key value (toJSONFields rest)
    where key = T.pack (nameVal (Proxy @name))
          value = toJSON v

class FromJSONFields sch fields where
  parseJSONFields :: Object -> Parser (NP (Field sch) fields)
instance FromJSONFields sch '[] where
  parseJSONFields _ = return Nil
instance forall sch name t fs.
         (KnownName name, FromJSON (FieldValue sch t), FromJSONFields sch fs)
         => FromJSONFields sch ('FieldDef name t ': fs) where
  parseJSONFields v = (:*) <$> (Field <$> v .: key) <*> parseJSONFields v
    where key = T.pack (nameVal (Proxy @name))

instance ToJSONEnum choices => ToJSON (Term sch ('DEnum name choices)) where
  toJSON (TEnum choice) = String (toJSONEnum choice)
instance FromJSONEnum choices => FromJSON (Term sch ('DEnum name choices)) where
  parseJSON (String s) = TEnum <$> parseJSONEnum s
  parseJSON _ = fail "expected string"

class ToJSONEnum choices where
  toJSONEnum :: NS Proxy choices -> T.Text
instance ToJSONEnum '[] where
  toJSONEnum = error "empty enum"
instance forall c cs. (KnownName c, ToJSONEnum cs)
         => ToJSONEnum (c ': cs) where
  toJSONEnum (Z _) = T.pack (nameVal (Proxy @c))
  toJSONEnum (S v) = toJSONEnum v

class FromJSONEnum choices where
  parseJSONEnum :: T.Text -> Parser (NS Proxy choices)
instance FromJSONEnum '[] where
  parseJSONEnum _ = fail "unknown enum value"
instance forall c cs. (KnownName c, FromJSONEnum cs)
         => FromJSONEnum (c ': cs) where
  parseJSONEnum v
    | v == key  = return (Z Proxy)
    | otherwise = S <$> parseJSONEnum v
    where key = T.pack (nameVal (Proxy @c))

instance ToJSON (FieldValue sch t) => ToJSON (Term sch ('DSimple t)) where
  toJSON (TSimple x) = toJSON x
instance FromJSON (FieldValue sch t) => FromJSON (Term sch ('DSimple t)) where
  parseJSON v = TSimple <$> parseJSON v

instance ToJSON (FieldValue sch 'TNull) where
  toJSON FNull = Null
instance ToJSON t => ToJSON (FieldValue sch ('TPrimitive t)) where
  toJSON (FPrimitive v) = toJSON v
instance ToJSONKey t => ToJSONKey (FieldValue sch ('TPrimitive t)) where
  toJSONKey = contramap FPrimitive toJSONKey
  toJSONKeyList = contramap (map FPrimitive) toJSONKeyList
instance ToJSON (Term sch (sch :/: t))
         => ToJSON (FieldValue sch ('TSchematic t)) where
  toJSON (FSchematic v) = toJSON v
instance ToJSON (FieldValue sch t)
         => ToJSON (FieldValue sch ('TOption t)) where
  toJSON (FOption v) = toJSON v
instance ToJSON (FieldValue sch t)
         => ToJSON (FieldValue sch ('TList t)) where
  toJSON (FList v) = toJSON v
instance (ToJSONKey (FieldValue sch k), ToJSON (FieldValue sch v))
         => ToJSON (FieldValue sch ('TMap k v)) where
  toJSON (FMap v) = toJSON v
-- TODO: missing unions!!

instance FromJSON (FieldValue sch 'TNull) where
  parseJSON Null = return FNull
  parseJSON _ = fail "expected nul"
instance FromJSON t => FromJSON (FieldValue sch ('TPrimitive t)) where
  parseJSON v = FPrimitive <$> parseJSON v
instance FromJSONKey t => FromJSONKey (FieldValue sch ('TPrimitive t)) where
  fromJSONKey = fmap FPrimitive fromJSONKey
  fromJSONKeyList = fmap (map FPrimitive) fromJSONKeyList
instance FromJSON (Term sch (sch :/: t))
         => FromJSON (FieldValue sch ('TSchematic t)) where
  parseJSON v = FSchematic <$> parseJSON v
instance FromJSON (FieldValue sch t)
         => FromJSON (FieldValue sch ('TOption t)) where
  parseJSON v = FOption <$> parseJSON v
instance FromJSON (FieldValue sch t)
         => FromJSON (FieldValue sch ('TList t)) where
  parseJSON v = FList <$> parseJSON v
instance ( FromJSONKey (FieldValue sch k), FromJSON (FieldValue sch v)
         , Ord (FieldValue sch k) )
         => FromJSON (FieldValue sch ('TMap k v)) where
  parseJSON v = FMap <$> parseJSON v