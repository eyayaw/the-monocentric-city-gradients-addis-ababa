EXAMPLES = """
**Input**: "betam konjo tsidit bilo yetesera condominum bet be lideta kondominium andegna fok lay hulum neger yalekelet konjo bet mulu ceramic yetesera kichin kabinet yalew konjo bet new 1 mignta 2 metatebiaya 5.5 sifatu 120 kare le nigid mehon yichilal. Bank bidir enamechachalen. እስከ 50,000ብር የሚካራይ ጋዢ በ0912403669 ይደውሉልን. Abebe https://t.me/broker_abebe"
**Output**:
```json
[
    {
        "type": "condominium",
        "listing": "for sale",
        "price": {
            "amount": 5500000, // Assuming 5.5 is referring to millions based on local context.
            "currency": "ETB",
            "type": "fixed", // from context
            "unit": "total" // from context
        },
        "size": {
            "floor_area": 120,
            "plot_area": null,
            "unit": "sqm" // 'kare' refers to sqm
        },
        "address": {
            "original": "lideta kondominium",
            "trans": "Lideta Condominium"
        },
        "features": {
            "counts": {
                "bedrooms": 1,
                "bathrooms": 2
            },
            "specifics": ["kitchen"]
            "description": "Beautiful and neatly-built"
        },
        "construction": {
            "year": null,
            "materials": ["ceramic"], // From "mulu ceramic" suggesting full ceramic.
            "condition": "new" // from context
        },
        "occupancy": {
        "rental_yield": 50000
        },
        "financing_options": "Bank loans available", // From "Bank bidir enamechachalen".
        "location": {
            "floor": 1 // From 'andegna' fok
        },
        "seller": {
            "name": "Abebe",
            "type": "individual",
            "contact": {
                "phone": "0912403669",
                "other": "t.me/broker_abebe"
            }
        },
        "remarks": "Transliterated text. Price 5.5 may be in millions. `listing_type` understood from context. Condominium scheme not specified. Can be used for commercial purposes."
    }
]
```
**Input**: "ሁል የተሟላለት ቅንጡ የመኖሪያ ቤት ኪራይ ሲምሲ ኮፓውንድ ውስጥ ካሬ ሜትር 600
መኝታ ቤት 6 ሳሎን 2 ኪችን2 ሻውር ሽንት ቤት 5 በቂ የመናፈሻ ስፍራ መኪና ማቆሚያ 6
ዋጋ140 ሽ ኮሚሽን 10% 0911067686x"
**Output**:
```json
[
    {
        "type": "house",
        "listing": "for rent",
        "price": {
            "amount": 140000, // 'ሽ' is understood as thousand.
            "currency": "ETB",
            "type": "fixed",
            "unit": "month"
        },
        "size": {
            "floor_area": 600,
            "plot_area": null,
            "unit": "sqm"
        },
        "address": {
            "original": "ሲምሲ ኮፓውንድ",
            "trans": "CMC Compound"
        },
        "features": {
            "counts": {
                "bedrooms": 6,
                "bathrooms": 5
            },
            "specifics": [
                "6 parking spaces",
                "relaxing space"
            ],
            "utilities": [],
            "amenities": [],
            "description": "luxurious",
            "view": "park"
        },
        "additional": {
            "furnishing": "fully furnished", // ሁሉ የተሟላለት -> everything equipped
        },
        "seller": {
            "contact": {
                "phone": "0911067686"
            }
        },
        "remarks": "Commission is 10%. \"ሽ\" understood as thousand. Sufficient relaxing space."
    }
]
```

**Input**: ⭐️አርሞንየም ሪል እስቴት\n\n  ➲ካርታ የተዘጋጀለት ፣ ጥንቅቅ ብሎ ያለቀ አፓርትማ ቤቶችን ለእርሶ!  \nበ 40% ቅድመ ክፋያ ብቻ\n\n  ➲ባለ 2 መኝታ - 114.8m² & 126.6m²\n  ➲ባለ 3 መኝታ 157.9m²
**Output**:
```json
[
    {
        "type": "apartment",
        "listing": "for sale",
        "address": {
            "original": "አርሞንየም",
            "trans": "Armonem"
        },
        "size": {
            "floor_area": 114.8,
            "plot_area": null,
            "unit": "sqm"
        },
        "construction": {
            "condition": "new"
        },
        "features": {
            "counts": {
                "bedrooms": 2
            }
        },
        "financing_options": "40% down payment"
    },
    {
        "type": "apartment",
        "listing": "for sale",
        "address": {
            "original": "አርሞንየም",
            "trans": "Armonem"
        },
        "size": {
            "floor_area": 126.6,
            "plot_area": null,
            "unit": "sqm"
        },
        "construction": {
            "condition": "new"
        },
        "features": {
            "counts": {
                "bedrooms": 2
            }
        },
        "financing_options": "40% down payment"
    },
    {
        "type": "apartment",
        "listing": "for sale",
        "address": {
            "original": "አርሞንየም",
            "trans": "Armonem"
        },
        "size": {
            "floor_area": 157.9,
            "plot_area": null,
            "unit": "sqm"
        },
        "construction": {
            "condition": "new"
        },
        "features": {
            "counts": {
                "bedrooms": 3
            }
        },
        "financing_options": "40% down payment"
    }
]
```

**Input**: bale ande megnetabet lmenoriya mechu ye 1 amet lemikfel asteyayet alw. sifatu 120 kare new. arif berenda alew.
**Output**:
```json
[
  {
    "type": "house",
    "listing": "for rent",
    "size": {
      "floor_area": 120, // 'sifatu' understood as area
      "plot_area": null,
      "unit": null
    },
    "address": {
      "original": null,
      "trans": null
    },
    "features": {
      "counts": {
        "bedrooms": 1, // bale ande megnetabet -> ባለ አንድ መኝታ ቤት
        "bathrooms": null
      },
      "specifics": ["balcony"],
      "utilities": [],
      "amenities": [],
      "description": "Comfortable for living, has amazing balcony", // lmenoriya mechu -> ለመኖሪያ ምቹ, berenda -> በረንዳ -> balcony
      "view": null
    },
    "financing_options": "Discount if paid for 1 year",
    "remarks": "Transliterated text. \'sifatu\' understood as \'area\'."
  }
]
``` 

**Input**: የሚሸጥ ቦታ\nመሪ ፀሀይ ሪልስቴት አካባቢ  ኮንባዉድ ዉስጥ  24 ሥአት ጥበቃ አይለዉ\n270 ካሬ ፈራሽ ቤት ያለው\nየአከባቢ ሁኔታ: ለትምህርት ቤቶች፣ ለሆስፒታሎች እና ለትራንስፖርት አመቺ የሆነ ቦታ ላይ ያለ ለዋነው አስፓልት ቅርብ የሆነ ፣ እንዲሁም ስላም እና ደንነቱ የተረጋገጠ አከባቢ ላይ የሚገኝ፡፡

```json
[
  {
    "type": "land",
    "listing": "for sale",
    "price": null,
    "address": {
      "original": "መሪ ፀሀይ ሪልስቴት አካባቢ", // (ኮንባዉድ -> ኮምፓውንድ) ዉስጥ -> inside compound: is irrelevant to the address
      "trans": "Meri Tsehay Real Estate Area"
    },
    "size": {
      "floor_area": 270,
      "plot_area": null,
      "unit": "sqm"
    },
    "construction": {
      "condition": null
    },
    "features": {
      "counts": {
        "bedrooms": null,
        "bathrooms": null
      },
      "specifics": ["24 hour security"],
      "utilities": [],
      "amenities": [],
      "description": null,
      "view": null
    },
    "location": {
      "floor": null,
      "local_attractions": [
        "schools",
        "hospitals",
        "transport"
      ],
      "accessibility": [
        "asphalt road"
      ]
    },
    "seller": {
      "name": null,
      "type": "individual",
      "contact": null
    },
    "remarks": "Peaceful and secure neighborhood. There is a demolishable house on it."
  }
]
``` 

**Input**: እጅግ ዉብ እና ዘመናዊ አፓርትመንት በመሐል ከተማ መካኒሳ ;ጀርመን አደባባይ ላይ።\n Finishing stage ላይ የደረሰ \n ለኑሮ ተስማሚ \n በካሬ 115ሺህ\n በ50% ቅደመ ክፍያ\n ባለ 2መኝታ 99ካሬ\n ቀሪዉን በ1ዓመት ከ6ወር ዉስጥ የሚከፍሉት።\nCall now \n+251 934 74 05 37\n+251 984 73 85 77
**Output**:
```json
[
  {
    "type": "apartment",
    "listing": "for sale",
    "price": {
      "amount": 115000, // '115ሺህ' 115 thousand
      "currency": "ETB", // from the context
      "type": null,
      "unit": "sqm"
    },
    "address": {
      "original": "መካኒሳ, ጀርመን አደባባይ",
      "trans": "Mekanisa, German Square"
    },
    "size": {
      "floor_area": 99,
      "plot_area": null,
      "unit": "sqm"
    },
    "construction": {
      "condition": "finishing stage"
    },
    "features": {
      "counts": {
        "bedrooms": 2,
        "bathrooms": null
      },
      "description": "suitable for living, located in city center",
      "view": null
    },
    "financing_options": "50% down payment, the remaining to be paid in 1 year and 6 months",
    "seller": {
      "contact": [
        "+251 934 74 05 37",
        "+251 984 73 85 77"
      ]
    },
    "remarks": null
  }
]
```

**Input**: ለሽያጭ የቀረበ ህንፃ @ቡልጋሪያ\n**************\n* ስፋት - 1,100 ካሬ(ጠቅላላ ስፋት)\n* 800 ካሬ ላይ ያረፈ ግንባታ\n* ለአፓርታማ የተገነባ\n* ዋጋ - 650 ሚልዮን (ድርድር አለው)\n\nለበለጠ መረጃ ይደውሉ\nPhone -  +251944781200\nEmail -   highclassbrokers@gmail.com\nTelegram - https://t.me/highclassbrokers\nHighClass_brokers/HC_brokersu
**Output**: [
      {
        "type": "apartment building", // from \'ህንፃ\' and \'ለአፓርታማ የተገነባ\'
        "listing": "for sale",
        "price": {
          "amount": 650000000,
          "currency": "ETB",
          "type": "Negotiable",
          "unit": "Total price"
        },
        "size": {
          "floor_area": 800,
          "plot_area": 1100,
          "unit": "sqm"
        },
        "seller": {
          "name": "HighClass_brokers/HC_brokersu",
          "type": "agency",
          "contact": {
            "phone": "+251944781200",
            "other": [
              "highclassbrokers@gmail.com",
              "https://t.me/highclassbrokers"
            ]
          }
        },
        "remarks": "The building rests on 800 sqm but the total plot size is 1100 sqm."
      }
    ]
```

**Input**: 📞0940077575 💥💥💥👍ውብ አረንጓዴ መንደር 💥💥💥 🌟 የማይታመን ውበት፣ የማይታመን ዋጋ! 🌟 💥7000ካሬ ላይ ያረፈ 💥ሰፊ ግቢ 💥ውብ ህንፃዎች፣ 💥ባለ አንድ መኝታ - 120ካሬ - 5ሚ ብር 💥 ባለ ሁለት መኝታ  200 ካሬ - 7.5 ሚ ብር 💥ባለ3መኝታ 250 ካሬ - 10 ሚ ብር 💥በ15% ብቻ ቅድመ ክፍያ 💥የከርሰ ምድር ውሃ 💥አረንጓዴ ስፍራ ያለው 💥ባንኮን በማይሰብር ዋጋ 💥24/7 የማይቋረጥ መብራት 💥ሁለት ዘመናዊ ሊፍት 📞 ዛሬውኑ ይወስኑ 0940077575 ይህ ወርቃማ እድል እንዳያመልጥዎ!
 **Output**: 
```json
[
    {
        "type": "apartment",
        "listing": "for sale",
        "price": {
            "amount": 5000000,
            "currency": "ETB",
            "type": "fixed, 15% down payment",
            "unit": "total price"
        },
        "address": null,
        "size": {
            "floor_area": 120,
            "plot_area": 7000,
            "unit": "sqm"
        },
        "features": {
            "counts": {
                "bedrooms": 1,
                "bathrooms": null
            },
            "specifics": [
                "green area",
                "24/7 uninterrupted electricity",
                "two modern elevators"
            ],
            "utilities": [
                "ground water"
            ],
            "amenities": [],
            "description": "beautiful green compound, amazing beauty, amazing price",
            "view": null
        },
        "financing_options": "15% down payment, bank financing available",
        "seller": {
            "contact": {"phone": "0940077575"}
        },
        "remarks": "Its apartment within a building. The floor area is not provided."
    },
    {
        "type": "apartment",
        "listing": "for sale",
        "price": {
            "amount": 7500000,
            "currency": "ETB",
            "type": "fixed, 15% down payment",
            "unit": "total price"
        },
        "address": null,
        "size": {
            "floor_area": 200,
            "plot_area": 7000,
            "unit": "sqm"
        },
        "features": {
            "counts": {
                "bedrooms": 1,
                "bathrooms": null
            },
            "specifics": [
                "green area",
                "24/7 uninterrupted electricity",
                "two modern elevators"
            ],
            "utilities": [
                "ground water"
            ],
            "amenities": [],
            "description": "beautiful green compound, amazing beauty, amazing price",
            "view": null
        },
        "financing_options": "15% down payment, bank financing available",
        "seller": {
            "contact": {"phone": "0940077575"}
        },
        "remarks": "Its apartment within a building. The floor area is not provided."
    },
    {
        "type": "apartment",
        "listing": "for sale",
        "price": {
            "amount": 10000000,
            "currency": "ETB",
            "type": "fixed, 15% down payment",
            "unit": "total price"
        },
        "address": null,
        "size": {
            "floor_area": 250,
            "plot_area": 7000,
            "unit": "sqm"
        },
        "features": {
            "counts": {
                "bedrooms": 1,
                "bathrooms": null
            },
            "specifics": [
                "green area",
                "24/7 uninterrupted electricity",
                "two modern elevators"
            ],
            "utilities": [
                "ground water"
            ],
            "amenities": [],
            "description": "beautiful green compound, amazing beauty, amazing price",
            "view": null
        },
        "financing_options": "15% down payment, bank financing available",
        "seller": {
            "contact": {"phone": "0940077575"}
        },
        "remarks": "Its apartment within a building. The floor area is not provided."
    }
]
```

**Input**: የሚከራይ አፓርትመንት 22 ጎላጉል 400ሜትር ገባ ብሎ ኮምፓውንድ ውስጥ የሚፈልጉት መኖርያ ኪራይ ወይም ሽያጭ በ አፓርትመንት, ኮንደምንየም, ቪላ, ፎቅ ከፈለጉ እኛ ጋ ይደውሉ\nያለንን ቦታ\n1.ቦሌ\n2. ገርጂ\n3.ቦሌ ቡልቡላ\n4. ሃያ ራት\n5. ሰሚት\n6. መገናኛ\n7. ለቡ\n8.02\n9. ጎሮ\n10ሳሪስ\nየሚከራይ ቤት ወይም የሚሽጥ ካሎት አብረን ለመስራት ዝግጁ ነን || Furnished 2bdrm Apartment in ሃያሁለት, Bole for Rent
**Output**: 
```json
[
      {
        "type": "apartment",
        "listing": "for rent",
        "address": {
          "original": "22 ጎላጉል",
          "trans": "22 Golagul"
        },
        "size": {
          "floor_area": null,
          "plot_area": null,
          "unit": null
        },
        "features": {
          "counts": {
            "bedrooms": 2,
            "bathrooms": null
          },
          "specifics": [],
          "utilities": [],
          "amenities": [],
          "description": "furnished",
          "view": null
        },
        "seller": {
          "name": null,
          "type": "individual",
          "contact": null
        },
        "remarks": "The apartment is located 400m away from 22 Golagul, inside a compound. The seller mentions additional addresses where they have apartments for rent."
      }
      ]
```
"""
