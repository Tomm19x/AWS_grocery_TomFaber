# app/controllers/product_controller.py
from flask import jsonify, request, current_app
from flask_jwt_extended import jwt_required, get_jwt_identity
from sqlalchemy.exc import DataError
from ..services.product_service import (
    get_all_products, get_product_by_id, add_review_to_product,
    remove_review_from_product, update_product_review
)
from ..services.user_service import get_user_info

def fetch_all_products():
    try:
        products = get_all_products()
        current_app.logger.info("Fetched all products.")
        return jsonify(products), 200
    except Exception as e:
        current_app.logger.error(f"Error fetching all products: {str(e)}")
        return jsonify({"error": "Unable to fetch products"}), 500

def get_single_product(product_id):
    try:
        product_id = int(product_id)
        current_app.logger.info(f"Fetching product with ID {product_id}.")
    except ValueError:
        return jsonify({"error": "Invalid product ID"}), 400
    try:
        product = get_product_by_id(product_id)
        if product:
            return jsonify(product), 200
        return jsonify({'error': 'Product not found'}), 404
    except DataError as e:
        return jsonify({"error": "Invalid product ID format"}), 400

@jwt_required()
def add_review(product_id):
    try:
        user_id = get_jwt_identity()
        user_info = get_user_info(user_id)
        if not user_info:
            return jsonify({"error": "User not found"}), 404
        review_data = request.json or {}
        review_data['author'] = user_info.get('username', 'Anonymous')
        response = add_review_to_product(product_id, review_data)
        return jsonify(response), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 400

@jwt_required()
def delete_review(product_id):
    try:
        data = request.get_json() or {}
        author_name = data.get('author_name')
        response = remove_review_from_product(product_id, author_name)
        return jsonify(response), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 400

@jwt_required()
def update_review(product_id):
    try:
        data = request.json or {}
        author_name = data.get('author_name')
        if not author_name:
            return jsonify({"error": "Author name is required"}), 400
        try:
            rating = int(data.get("rating"))
            if rating < 1 or rating > 5:
                return jsonify({"error": "Rating must be between 1 and 5"}), 400
        except (ValueError, TypeError):
            return jsonify({"error": "Invalid rating value"}), 400
        updated_data = {"rating": rating, "comment": data.get("comment")}
        if updated_data["comment"] is None:
            return jsonify({"error": "Comment is required"}), 400
        response = update_product_review(product_id, author_name, updated_data)
        return jsonify(response), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 400
