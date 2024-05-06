PROPERTY_SCHEMA = """
[
    {
        "type": "str", // e.g., house, apartment, land, apartment building, commercial building, warehouse, office, shop, etc.
        "listing": "str", // e.g., for sale, rent, lease
        "price": {
            "amount": "float", // Rental fees for rentals, land prices for land, etc.
            "currency": "str", // e.g., ETB, USD
            "type": "str", // e.g., fixed, negotiable, discounted, downpayment/installment, etc.
            "unit": "str" // e.g., Total price, per sqm, per month, etc.
        },
        "address": { // The full address of the property
            "original": "str", // The original address in the ad correcting minor typos.
            "trans": "str" // Address transliterated in ascii characters. Retain the original address formats while ensuring readable transliterations.
        },
        "size": {
            "floor_area": "float", // NB: "ካሬ (ሜትር)", (k/c)are, m², m2 denote sqm. This is the size of the land for the property type "land".
            "plot_area": "float", // The total plot area, if applicable. Apartment buildings, detached houses, commercial buildings, warehouses, may have plot area info in addition to floor area.
            "unit": "str"
        },
        "construction": {
            "year": "int",
            "materials": "str", // e.g., brick, wood
            "condition": "str" // e.g., new, renovated
        },
        "features": { // Detailed features of the property
            "counts": {
                "bedrooms": "int",
                "bathrooms": "int",
                "units": "int", // If applicable, for multi-unit buildings.
                "floors": "int"
            },
            "specifics": ["str"], // e.g., balcony, fully-ceramic
            "utilities": ["str"], // e.g., water, electricity
            "amenities": ["str"], // e.g., gym, pool, backyard, garden
            "description": "str", // e.g., beautiful, modern
            "view": "str" // e.g., mountain, city, park
        },
        "occupancy": {
            "status": "str", // e.g., vacant, occupied
            "rental_yield": "float" // Potential rental income or yield
        },
        "financing_options": "str", // e.g., mortgages, installements
        "location": {
            "floor": "int", // Floor number, for multi-story
            "local_attractions": ["str"], // Nearby attractions
            "accessibility": ["str"] // e.g., public transport
        },
        "additional": {
            "basement": "bool",
            "furnishing": "str", // e.g., un/semi/fully furnished
            "pets_allowed": "bool"
        },
        "seller": {
            "name": "str",
            "type": "str", // e.g., individual, agency
            "contact": {
                "phone": "str",
                "other": "str" // e.g., email, website
            }
        },
        "remarks": "str" // Additional notes about the property.
    }
]
"""
